module Media
  # Turns a freshly attached raw profile-video upload into the safe playback
  # rendition + poster frame that other eligible users may see (ADR 0023).
  #
  #   raw original (private) -> full ISO-BMFF structural validation -> brand
  #   duration limit -> ffprobe -> H.264/AAC MP4 rendition (+ stream-copy or
  #   no-op when already compatible) -> poster frame -> store derivatives
  #   (private) -> mark ready -> purge raw original
  #
  # The structural walk (Media::VideoContainerValidator) and duration check run
  # HERE, against the whole downloaded object — a bounded head cannot contain a
  # non-faststart MP4's trailing `moov` box, so validating at attach time would
  # reject legitimate uploads. A structurally invalid file or one over the
  # brand's duration limit is a terminal `failed` state.
  #
  # Concurrency-safe (ADR 0028 §6 / ADR 0029 Pass 2B), mirroring
  # Media::ProcessProfilePhotoJob. A short CLAIM transaction takes a per-run
  # token; expensive ffmpeg/ffprobe/storage work AND the full remote validation
  # of an existing ready run happen OUTSIDE any transaction; a short FINALIZE
  # transaction attaches the derivatives only while this run still owns the
  # claim token. A worker that crashes after claiming leaves a stale
  # `processing` row the sweeper (Media::ProfileVideoProcessingSweeper)
  # reclaims. The ABA guard is the token: a stale worker that wakes after a
  # reclaim CANNOT finalize, purge, or mutate state.
  class ProcessProfileVideoJob < ApplicationJob
    queue_as :default

    class TransientError < StandardError; end

    MAX_ATTEMPTS = 5

    retry_on TransientError, wait: :polynomially_longer, attempts: MAX_ATTEMPTS
    discard_on ActiveJob::DeserializationError

    def perform(profile_video_id)
      video = ProfileVideo.find_by(id: profile_video_id)
      return if video.nil? || video.deleted_at.present?

      @token = SecureRandom.uuid

      case claim!(video.id)
      when :claimed
        process_claimed(video.id)
      when :verify_ready
        reconcile_ready(video.id)
      end
      # :terminal / :in_progress / :gone / :noop -> nothing to do
    rescue TransientError
      release_claim(profile_video_id, terminal: executions >= MAX_ATTEMPTS)
      raise
    end

    private

    # --- CLAIM (short txn) --------------------------------------------------

    def claim!(video_id)
      outcome = :noop
      ProfileVideo.transaction do
        video = ProfileVideo.lock.find(video_id)
        outcome =
          if video.deleted_at.present?
            :noop
          elsif video.processing_ready?
            :verify_ready # confirm/repair OUTSIDE this lock (no remote I/O here)
          elsif video.processing_terminal_failure?
            :terminal
          elsif video.processing_retryable?
            video.update!(processing_state: :processing, processing_started_at: Time.current,
              processing_claim_token: @token)
            :claimed
          elsif video.processing_started_at.present? &&
                video.processing_started_at >= ProfileVideo::STALE_PROCESSING_AFTER.ago
            :in_progress
          else
            video.update!(processing_started_at: Time.current, processing_claim_token: @token) # reclaim stale
            :claimed
          end
      end
      outcome
    rescue ActiveRecord::RecordNotFound
      :gone
    end

    # --- WORK (no transaction) -------------------------------------------

    def process_claimed(video_id)
      video = ProfileVideo.find_by(id: video_id)
      return if video.nil? || video.deleted_at.present?

      unless video.video.attached?
        finalize_ready_or_release(video_id)
        return
      end

      raw = download_raw(video)
      container = validate_container(video, raw)
      return if container.nil? # terminal failure recorded
      return if over_duration?(video, container.duration_seconds, source: "container")

      result = safely_process(video, raw)
      return if result.nil? # terminal failure recorded
      return if over_duration?(video, result.duration_seconds, source: "probe")

      finalize!(video_id, result)
    end

    def download_raw(video)
      video.video.download
    rescue StandardError => e
      raise TransientError, "raw download failed: #{e.class}"
    end

    def validate_container(video, raw)
      Media::VideoContainerValidator.call(raw)
    rescue Media::VideoContainerValidator::Error => e
      mark_terminal_failure(video.id, "invalid_container")
      Rails.logger.warn("[media] profile_video=#{video.id} rejected: invalid container: #{e.class}")
      nil
    end

    def over_duration?(video, duration_seconds, source:)
      return false if duration_seconds.nil?

      limit = Media::VideoPolicy.max_duration_seconds(brand: video.brand)
      return false if duration_seconds <= limit

      mark_terminal_failure(video.id, "duration_over_limit")
      Rails.logger.warn("[media] profile_video=#{video.id} rejected: #{source} duration #{duration_seconds}s > #{limit}s")
      true
    end

    def safely_process(video, raw)
      Media::VideoProcessor.call(raw)
    rescue Media::VideoProcessor::TimedOut
      raise TransientError, "video processing timed out"
    rescue Media::VideoProcessor::Error => e
      mark_terminal_failure(video.id, "processing_failed")
      Rails.logger.warn("[media] profile_video=#{video.id} processing failed: #{e.class}")
      nil
    end

    # --- FINALIZE (A: locate/create -> B: validate out of lock -> C/D: short txn)
    #
    # Review Finding 1: an existing deterministic-key derivative blob may be
    # REUSED only after its ACTUAL remote bytes are independently validated
    # (Media::PlaybackDerivative). Deterministic key identity alone is never
    # sufficient, and a validation-failing candidate is NEVER attached, NEVER
    # marks ready, NEVER purges the raw.

    def finalize!(video_id, result)
      video = ProfileVideo.find_by(id: video_id)
      return if video.nil? || video.deleted_at.present? || !video.video.attached?

      raw_key = video.video.blob.key
      keys = derivative_keys(raw_key)
      service = video.video.blob.service_name.to_s

      if result.poster_bytes.blank?
        mark_terminal_failure(video_id, "poster_missing")
        return
      end

      # A. locate the candidate derivative blob at each deterministic key, or
      #    create+upload the freshly computed bytes. An existing key is NEVER
      #    overwritten here.
      playback_blob = locate_or_create_blob(keys[:playback], result.rendition_bytes, "video/mp4",
        Media::ObjectKey::PLAYBACK_BASENAME, service)
      poster_blob = locate_or_create_blob(keys[:poster], result.poster_bytes, "image/jpeg",
        Media::ObjectKey::POSTER_BASENAME, service)

      # B. validate the CANDIDATE remote bytes OUTSIDE every DB lock.
      unless Media::PlaybackDerivative.playback_blob_valid?(
        blob: playback_blob, expected_key: keys[:playback], expected_service: service
      )
        raise TransientError, "candidate playback derivative failed validation"
      end
      unless Media::PlaybackDerivative.poster_blob_valid?(
        blob: poster_blob, expected_key: keys[:poster], expected_service: service
      )
        raise TransientError, "candidate poster derivative failed validation"
      end

      validated = { playback: derivative_fingerprint(playback_blob), poster: derivative_fingerprint(poster_blob) }

      finalized = false
      conflict = false

      ProfileVideo.transaction do
        locked = ProfileVideo.lock.find(video_id)
        next if locked.deleted_at.present?
        next unless owns_claim?(locked) # lost claim -> discard, do NOT mutate state

        # D. the exact validated candidates must STILL be the blob rows at those
        #    keys (defeats a candidate swap between B and C).
        current_playback = ActiveStorage::Blob.find_by(key: keys[:playback])
        current_poster = ActiveStorage::Blob.find_by(key: keys[:poster])
        if derivative_fingerprint(current_playback) != validated[:playback] ||
           derivative_fingerprint(current_poster) != validated[:poster]
          conflict = true
          next
        end

        conflict = !attach_validated_derivative(locked, :playback, current_playback, validated[:playback]) ||
          !attach_validated_derivative(locked, :poster, current_poster, validated[:poster])
        next if conflict

        mark_ready!(locked, result, raw_key:, keys:, service:)
        finalized = true
      end

      if conflict
        mark_terminal_failure(video_id, "derivative_conflict")
        Rails.logger.warn("[media] profile_video=#{video_id} conflicting/invalid derivative; failed closed")
      elsif finalized
        video.reload
        video.video.purge_later if video.processing_ready? && video.video.attached?
      end
    rescue ActiveRecord::RecordNotFound
      nil
    rescue TransientError
      raise
    rescue StandardError => e
      raise TransientError, "derivative persist failed: #{e.class}"
    end

    # Deterministic keys -> a retry that already uploaded reuses the blob row.
    # An existing key is never overwritten (validation, not trust, gates reuse).
    def locate_or_create_blob(key, bytes, content_type, basename, service_name)
      ActiveStorage::Blob.find_by(key:) || ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new(bytes), key:, filename: basename, content_type:, service_name:
      )
    rescue ActiveRecord::RecordNotUnique
      ActiveStorage::Blob.find_by(key:)
    end

    # Stable identity of a candidate/attached derivative blob — an ABA guard: if
    # the row at a deterministic key is swapped between validation and finalize,
    # the fingerprint changes and finalize fails closed.
    def derivative_fingerprint(blob)
      return nil if blob.nil?

      [ blob.id, blob.key, blob.checksum, blob.byte_size, blob.content_type, blob.service_name ].map(&:to_s)
    end

    # @return [Boolean] true only when the attachment points at EXACTLY the
    #   independently-validated blob.
    def attach_validated_derivative(video, name, validated_blob, expected_fingerprint)
      attachment = video.public_send(name)
      if attachment.attached?
        derivative_fingerprint(attachment.blob) == expected_fingerprint
      else
        attachment.attach(validated_blob)
        true
      end
    end

    # Reached from process_claimed when the raw is already purged: confirm the
    # derivatives (out of lock), then commit ready or fail closed.
    def finalize_ready_or_release(video_id)
      video = ProfileVideo.find_by(id: video_id)
      return if video.nil?

      ok = derivatives_valid?(video) # strong, out of lock

      ProfileVideo.transaction do
        locked = ProfileVideo.lock.find(video_id)
        next unless owns_claim?(locked)

        if ok
          locked.update!(processing_state: :ready, processed_at: Time.current,
            processing_started_at: nil, processing_claim_token: nil)
        else
          mark_terminal_failure!(locked, "derivative_unrecoverable")
        end
      end
    rescue ActiveRecord::RecordNotFound
      nil
    end

    # --- READY RECONCILIATION (no transaction) --------------------------

    def reconcile_ready(video_id)
      video = ProfileVideo.find_by(id: video_id)
      return if video.nil? || video.deleted_at.present? || !video.processing_ready?
      return if derivatives_valid?(video)

      if video.video.attached?
        return unless reclaim_for_repair!(video_id) == :claimed

        process_claimed(video_id)
      else
        fail_unrecoverable_ready!(video_id)
      end
    end

    def reclaim_for_repair!(video_id)
      outcome = :noop
      ProfileVideo.transaction do
        video = ProfileVideo.lock.find(video_id)
        next if video.deleted_at.present? || !video.video.attached?
        next unless video.processing_ready? || video.processing_failed?

        video.update!(processing_state: :processing, processing_started_at: Time.current,
          processing_claim_token: @token)
        outcome = :claimed
      end
      outcome
    rescue ActiveRecord::RecordNotFound
      :noop
    end

    def fail_unrecoverable_ready!(video_id)
      ProfileVideo.transaction do
        video = ProfileVideo.lock.find(video_id)
        next if video.deleted_at.present?
        next unless video.processing_ready? && !video.video.attached?

        mark_terminal_failure!(video, "derivative_unrecoverable")
      end
      Rails.logger.warn("[media] profile_video=#{video_id} ready with unrecoverable derivatives; failed closed")
    rescue ActiveRecord::RecordNotFound
      nil
    end

    # --- shared -----------------------------------------------------

    def derivative_keys(raw_key)
      { playback: Media::ObjectKey.profile_video_playback(raw_key),
        poster: Media::ObjectKey.profile_video_poster(raw_key) }
    end

    def mark_ready!(video, result, raw_key:, keys:, service:)
      updates = {
        processing_state: :ready, processed_at: Time.current,
        processing_started_at: nil, processing_claim_token: nil,
        metadata: video.metadata.merge(
          "raw_object_key" => raw_key,
          "playback_object_key" => keys[:playback],
          "poster_object_key" => keys[:poster],
          "derivative_service_name" => service.to_s
        )
      }
      updates[:duration_seconds] = result.duration_seconds.floor if result.duration_seconds
      video.update!(updates)
    end

    def mark_terminal_failure(video_id, reason = nil)
      ProfileVideo.transaction do
        video = ProfileVideo.lock.find(video_id)
        next unless owns_claim?(video)

        mark_terminal_failure!(video, reason)
      end
    rescue ActiveRecord::RecordNotFound
      nil
    end

    def mark_terminal_failure!(video, reason = nil)
      meta = video.metadata.merge("processing_failure_kind" => "terminal")
      meta["processing_failure_reason"] = reason if reason
      video.update!(processing_state: :failed, processing_started_at: nil,
        processing_claim_token: nil, metadata: meta)
    end

    def release_claim(video_id, terminal:)
      return if @token.nil?

      ProfileVideo.transaction do
        video = ProfileVideo.lock.find(video_id)
        next unless owns_claim?(video)

        if terminal
          mark_terminal_failure!(video, "processing_transient_exhausted")
        else
          video.update!(processing_state: :failed, processing_started_at: nil, processing_claim_token: nil)
        end
      end
    rescue ActiveRecord::RecordNotFound
      nil
    end

    def owns_claim?(video)
      video.processing_processing? && video.processing_claim_token == @token
    end

    # Full bounded remote validation of the exact accepted deterministic
    # playback + poster pair. MUST run outside any DB lock / transaction.
    def derivatives_valid?(video)
      keys = expected_derivative_keys(video)
      return false if keys.nil?

      Media::PlaybackDerivative.valid?(
        video:, expected_playback_key: keys[:playback], expected_poster_key: keys[:poster],
        expected_service: expected_service(video)
      )
    end

    # Metadata-only — safe inside a transaction. nil when it cannot be proven.
    def expected_derivative_keys(video)
      if video.video.attached?
        derivative_keys(video.video.blob.key)
      else
        raw = video.metadata["raw_object_key"].presence
        playback = video.metadata["playback_object_key"].presence
        poster = video.metadata["poster_object_key"].presence
        return nil if raw.nil? || playback.nil? || poster.nil?

        expected = derivative_keys(raw)
        return nil unless playback == expected[:playback] && poster == expected[:poster]

        expected
      end
    end

    def expected_service(video)
      return video.video.blob.service_name.to_s if video.video.attached?

      video.metadata["derivative_service_name"].presence ||
        Media::StorageResolver.service_name(brand: video.brand).to_s
    end
  end
end
