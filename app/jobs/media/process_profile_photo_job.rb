module Media
  # Asynchronously turns a freshly attached raw profile-photo upload into the
  # safe display derivative that other eligible users may see.
  #
  #   raw original (private) -> decode -> re-encode -> strip metadata ->
  #   store display derivative (private) -> mark ready -> purge raw original
  #
  # Concurrency-safe (MEDIA-TRANSFER.md §16b). A short CLAIM transaction takes a
  # per-run token; expensive libvips/storage work AND the full remote validation
  # of an existing display run OUTSIDE any transaction; a short FINALIZE
  # transaction attaches the derivative only while this run still owns the claim
  # token. A worker that crashes after claiming leaves a stale `processing` row
  # the sweeper reclaims. The ABA guard is the token: a stale worker that wakes
  # after a reclaim CANNOT finalize, purge, or mutate state.
  #
  # "Complete" is proven by ONE authoritative contract — Media::DisplayDerivative
  # .valid? — a bounded remote read of the exact deterministic display artifact.
  # No weaker metadata-only definition is reachable as a success path.
  class ProcessProfilePhotoJob < ApplicationJob
    queue_as :default

    class TransientError < StandardError; end

    MAX_ATTEMPTS = 5

    retry_on TransientError, wait: :polynomially_longer, attempts: MAX_ATTEMPTS
    discard_on ActiveJob::DeserializationError

    def perform(profile_photo_id)
      photo = ProfilePhoto.find_by(id: profile_photo_id)
      return if photo.nil? || photo.deleted_at.present?

      @token = SecureRandom.uuid

      case claim!(photo.id)
      when :claimed
        process_claimed(photo.id)
      when :verify_ready
        # Full remote validation of the existing display must NOT run under the
        # CLAIM lock. Confirm the completed transfer, or repair / fail closed.
        reconcile_ready(photo.id)
      end
      # :terminal / :in_progress / :gone / :noop -> nothing to do
    rescue TransientError
      release_claim(profile_photo_id, terminal: executions >= MAX_ATTEMPTS)
      raise
    end

    private

    # --- CLAIM (short txn) ---------------------------------------------

    def claim!(photo_id)
      outcome = :noop
      ProfilePhoto.transaction do
        photo = ProfilePhoto.lock.find(photo_id)
        outcome =
          if photo.deleted_at.present?
            :noop
          elsif photo.processing_ready?
            :verify_ready # confirm/repair OUTSIDE this lock (no remote I/O here)
          elsif photo.processing_terminal_failure?
            :terminal
          elsif photo.processing_pending? || (photo.processing_failed? && !photo.processing_terminal_failure?)
            photo.update!(processing_state: :processing, processing_started_at: Time.current,
              processing_claim_token: @token)
            :claimed
          elsif photo.processing_started_at.present? &&
                photo.processing_started_at >= ProfilePhoto::STALE_PROCESSING_AFTER.ago
            :in_progress
          else
            photo.update!(processing_started_at: Time.current, processing_claim_token: @token) # reclaim stale
            :claimed
          end
      end
      outcome
    rescue ActiveRecord::RecordNotFound
      :gone
    end

    def process_claimed(photo_id)
      photo = ProfilePhoto.find_by(id: photo_id)
      return if photo.nil? || photo.deleted_at.present?

      unless photo.image.attached?
        finalize_ready_or_release(photo_id)
        return
      end

      raw = download_raw(photo)
      result = safely_process(photo, raw)
      return if result.nil? # terminal failure already recorded

      finalize!(photo_id, result)
    end

    # --- READY RECONCILIATION (no transaction) -----------------------
    #
    # Reached when CLAIM saw `processing_ready?`. The ONLY proof of a completed
    # transfer is a full bounded remote validation of the exact deterministic
    # display artifact. If it fails: rebuild from the still-present raw, or (raw
    # already purged) record an honest terminal failure — never trust it.

    def reconcile_ready(photo_id)
      photo = ProfilePhoto.find_by(id: photo_id)
      return if photo.nil? || photo.deleted_at.present? || !photo.processing_ready?
      return if display_valid?(photo)

      if photo.image.attached?
        return unless reclaim_for_repair!(photo_id) == :claimed

        process_claimed(photo_id)
      else
        fail_unrecoverable_ready!(photo_id)
      end
    end

    def reclaim_for_repair!(photo_id)
      outcome = :noop
      ProfilePhoto.transaction do
        photo = ProfilePhoto.lock.find(photo_id)
        next if photo.deleted_at.present? || !photo.image.attached?
        next unless photo.processing_ready? || photo.processing_failed?

        photo.update!(processing_state: :processing, processing_started_at: Time.current,
          processing_claim_token: @token)
        outcome = :claimed
      end
      outcome
    rescue ActiveRecord::RecordNotFound
      :noop
    end

    def fail_unrecoverable_ready!(photo_id)
      ProfilePhoto.transaction do
        photo = ProfilePhoto.lock.find(photo_id)
        next if photo.deleted_at.present?
        next unless photo.processing_ready? && !photo.image.attached?

        photo.update!(
          processing_state: :failed, processing_started_at: nil, processing_claim_token: nil,
          metadata: photo.metadata.merge(
            "processing_failure_kind" => "terminal", "processing_failure_reason" => "display_unrecoverable"
          )
        )
      end
      Rails.logger.warn("[media] profile_photo=#{photo_id} ready with an unrecoverable display; failed closed")
    rescue ActiveRecord::RecordNotFound
      nil
    end

    # --- WORK (no transaction) --------------------------------------

    def download_raw(photo)
      photo.image.download
    rescue StandardError => e
      raise TransientError, "raw download failed: #{e.class}"
    end

    def safely_process(photo, raw)
      Media::ImageProcessor.call(raw)
    rescue Media::ImageProcessor::Error => e
      mark_terminal_failure(photo.id)
      Rails.logger.warn("[media] profile_photo=#{photo.id} processing failed: #{e.class}")
      nil
    end

    # --- FINALIZE (short txn) -------------------------------------

    def finalize!(photo_id, result)
      photo = ProfilePhoto.find_by(id: photo_id)
      return if photo.nil? || photo.deleted_at.present? || !photo.image.attached?

      expected_key = Media::ObjectKey.profile_photo_display(photo.image.blob.key)
      # Validate an already-attached display with the full bounded remote check
      # BEFORE taking the finalize lock — never remote I/O under a DB lock.
      preexisting_ok = photo.display_image.attached? && display_valid?(photo)
      blob = preexisting_ok ? nil : derivative_blob(photo, result, expected_key)

      finalized = false
      conflict = false

      ProfilePhoto.transaction do
        locked = ProfilePhoto.lock.find(photo_id)
        next if locked.deleted_at.present?
        next unless owns_claim?(locked) # lost claim -> discard, do NOT mutate state

        if locked.display_image.attached?
          if preexisting_ok && locked.display_image.blob.key == expected_key
            mark_ready!(locked)
            finalized = true
          else
            mark_terminal_failure!(locked)
            conflict = true
          end
        else
          locked.display_image.attach(blob)
          mark_ready!(locked)
          finalized = true
        end
      end

      if conflict
        Rails.logger.warn("[media] profile_photo=#{photo_id} conflicting/invalid derivative; failed closed")
      elsif finalized
        # Purge the raw ONLY after a committed, owned, valid finalization.
        photo.reload
        photo.image.purge_later if photo.processing_ready? && photo.image.attached?
      end
    rescue ActiveRecord::RecordNotFound
      nil
    rescue TransientError
      raise
    rescue StandardError => e
      raise TransientError, "derivative persist failed: #{e.class}"
    end

    def finalize_ready_or_release(photo_id)
      photo = ProfilePhoto.find_by(id: photo_id)
      return if photo.nil?

      ok = display_valid?(photo) # strong, out of lock

      ProfilePhoto.transaction do
        locked = ProfilePhoto.lock.find(photo_id)
        next unless owns_claim?(locked)

        if ok && locked.display_image.attached?
          mark_ready!(locked)
        else
          mark_terminal_failure!(locked)
        end
      end
    rescue ActiveRecord::RecordNotFound
      nil
    end

    def release_claim(photo_id, terminal:)
      return if @token.nil?

      ProfilePhoto.transaction do
        photo = ProfilePhoto.lock.find(photo_id)
        next unless owns_claim?(photo)

        if terminal
          mark_terminal_failure!(photo)
        else
          photo.update!(processing_state: :failed, processing_started_at: nil, processing_claim_token: nil)
        end
      end
    rescue ActiveRecord::RecordNotFound
      nil
    end

    def mark_terminal_failure(photo_id)
      ProfilePhoto.transaction do
        photo = ProfilePhoto.lock.find(photo_id)
        next unless owns_claim?(photo)

        mark_terminal_failure!(photo)
      end
    rescue ActiveRecord::RecordNotFound
      nil
    end

    def mark_terminal_failure!(photo)
      photo.update!(
        processing_state: :failed, processing_started_at: nil, processing_claim_token: nil,
        metadata: photo.metadata.merge("processing_failure_kind" => "terminal")
      )
    end

    def mark_ready!(photo)
      photo.update!(
        processing_state: :ready, processed_at: Time.current,
        processing_started_at: nil, processing_claim_token: nil,
        metadata: photo.metadata.merge(display_key_metadata(photo))
      )
    end

    # Persisted authoritative state (ADR 0028) that lets the deterministic
    # display key be re-derived AFTER the raw original is purged. Not a new
    # table — the existing ProfilePhoto#metadata jsonb. PII-free (Media::ObjectKey).
    def display_key_metadata(photo)
      return {} unless photo.image.attached? && photo.display_image.attached?

      {
        "raw_object_key" => photo.image.blob.key,
        "display_object_key" => photo.display_image.blob.key,
        "display_service_name" => photo.display_image.blob.service_name.to_s
      }
    end

    def owns_claim?(photo)
      photo.processing_processing? && photo.processing_claim_token == @token
    end

    # The authoritative expected deterministic display key. Metadata-only — safe
    # inside a transaction. `nil` when it cannot be proven (fail closed).
    def expected_display_key(photo)
      if photo.image.attached?
        Media::ObjectKey.profile_photo_display(photo.image.blob.key)
      else
        key = photo.metadata["display_object_key"].presence
        raw = photo.metadata["raw_object_key"].presence
        return nil if key.nil? || raw.nil?

        # Prove the persisted display key really is the deterministic derivative
        # of the persisted original key — not an arbitrary stored string.
        key == Media::ObjectKey.profile_photo_display(raw) ? key : nil
      end
    end

    def expected_display_service(photo)
      return photo.image.blob.service_name.to_s if photo.image.attached?

      photo.metadata["display_service_name"].presence ||
        Media::StorageResolver.service_name(brand: photo.brand).to_s
    end

    # Full bounded remote validation of the exact accepted deterministic display
    # artifact. MUST run outside any DB lock / transaction.
    def display_valid?(photo)
      key = expected_display_key(photo)
      return false if key.nil?

      Media::DisplayDerivative.valid?(
        photo:, expected_display_key: key, expected_service: expected_display_service(photo)
      )
    end

    # Deterministic display key -> a retry that already uploaded reuses the blob.
    def derivative_blob(photo, result, key)
      ActiveStorage::Blob.find_by(key:) || ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new(result.bytes),
        key:,
        filename: Media::ObjectKey::DISPLAY_BASENAME,
        content_type: result.content_type,
        service_name: photo.image.blob.service_name
      )
    end
  end
end
