# frozen_string_literal: true

module Date9ja
  module Import
    # WAVE A — profile-video legacy migration (ADR 0029). Consumes the Pass-1
    # preflight graph (Migration::MediaObjectRef / MediaAttachmentRef) + the
    # controlled source-storage locator. Two stages, one orchestrator:
    #
    #   stage: :adopt (Pass 2A) — per source video:
    #     RESOLVE  owner Profile via Migration::ReferenceMap
    #     PHASE A  Migration::MediaTransfer.call(media_kind: MediaKind::Video):
    #              source bytes -> exact size/checksum vs MediaObjectRef
    #              -> ISO-BMFF type detect == preflighted type
    #              -> Media::VideoContainerValidator -> authoritative ffprobe
    #              duration -> Date9ja duration-policy gate
    #              -> deterministic CanonicalKey + AdoptOrUpload
    #     Maximum success: SOURCE_ACCEPTED / DESTINATION_ADOPTED. NOT transferred.
    #     Creates NO ProfileVideo / binding / job / derivative.
    #
    #   stage: :domain (Pass 2B) — after a successful adoption, additionally:
    #     RESOLVE  authoritative existing-chain check (idempotent resume)
    #     PHASE B  short LockGuard-held transaction: re-lock MediaAttachmentRef,
    #              re-resolve owner, re-prove the deterministic blob, one-live-
    #              video invariant, moderation map -> Profiles::VideoUpload
    #              .build_video! -> Migration::ReferenceMap.bind!
    #     PHASE C  after commit: Media::ProcessProfileVideoJob -> validated
    #              playback + poster (Media::PlaybackDerivative) -> ready ->
    #              existing raw-original purge behaviour.
    #     Maximum success: a fully domain-migrated ProfileVideo (`ready`).
    #
    # No remote I/O (R2 read, ffprobe, ffmpeg, derivative validation) ever runs
    # under a DB lock; Migration::MediaTransfer::RemoteIOUnderLock stays fatal.
    class VideoTransfer
      SOURCE_SYSTEM = "date9ja"
      OWNER_ENTITY = "profile"
      VIDEO_ENTITY = "profile_video"
      ATTACHMENT_NAME = "video"
      IMPORTER_VERSION = "date9ja-video-transfer-v1"
      DESTINATION_PURPOSE = "profile_video_original"
      EXPECTED_SOURCE_SERVICE = "cloudflare"
      DEFAULT_DRAIN_TIMEOUT = 60.seconds

      VIDEO_KIND = Migration::MediaTransfer::MediaKind::Video

      # Date9ja immediate-publication policy (ADR 0023) — identical shape to the
      # profile-photo mapping. `pending` stays visible; `rejected` is hidden.
      MODERATION_MAP = {
        "pending" => { status: :pending_review, visibility: :visible },
        "approved" => { status: :approved, visibility: :visible },
        "rejected" => { status: :rejected, visibility: :hidden }
      }.freeze

      Result = Data.define(:reconciliation)

      class WrongBrand < StandardError; end

      def self.call(...) = new(...).call

      def initialize(brand:, source:, locator:, source_reader:, media_transfer: Migration::MediaTransfer,
        importer_version: IMPORTER_VERSION, stage: :adopt, processing: :inline,
        drain_timeout: DEFAULT_DRAIN_TIMEOUT)
        raise ArgumentError, "stage must be :adopt or :domain" unless %i[adopt domain].include?(stage)

        @brand = brand
        @source = source
        @locator = locator
        @source_reader = source_reader
        @media_transfer = media_transfer
        @importer_version = importer_version
        @stage = stage
        @processing = processing
        @drain_timeout = drain_timeout
        @reconciliation = VideoTransferReconciliation.new(stage:)
        @owner_cache = {}
      end

      def call
        assert_brand!
        records = @source.to_a
        assert_single_source_service!(records)
        @reconciliation.measure!(:total_source_videos, records.size, mode: :set)

        records.group_by(&:owner_source_id).each do |owner_source_id, owned|
          @reconciliation.measure!(:owners_considered)
          transfer_owner(owner_source_id, owned)
        end

        Result.new(@reconciliation)
      end

      private

      attr_reader :brand, :reconciliation

      def dest_service = Media::StorageResolver.service_name(brand:).to_s

      def assert_brand!
        return if brand&.slug == SOURCE_SYSTEM && brand.active? && brand.deleted_at.nil?

        raise WrongBrand, "video transfer requires the active date9ja brand"
      end

      # Global blocker: any video blob on a service other than `cloudflare`.
      def assert_single_source_service!(records)
        blob_ids = records.filter_map { |r| r.video_attachment&.blob&.source_id }
        offenders = blob_ids.filter_map { |bid| @locator.call(bid)&.service_name }
          .reject { |name| name == EXPECTED_SOURCE_SERVICE }.uniq
        return if offenders.empty?

        raise Migration::MediaTransfer::GlobalBlocker,
          "date9ja video blobs on unexpected storage service(s): #{offenders.sort.join(', ')}"
      end

      def duration_limit_seconds
        @duration_limit_seconds ||= Media::VideoPolicy.max_duration_seconds(brand:)
      rescue Media::VideoPolicy::NotConfigured
        Media::VideoPolicy::DEFAULT_MAX_DURATION_SECONDS
      end

      # D8N permits at most one live ProfileVideo per profile (DB partial-unique
      # index). Pass 1 already quarantines a multi-video owner; re-guard here
      # rather than arbitrarily choosing one.
      def transfer_owner(owner_source_id, owned)
        if owned.size > 1
          owned.each do
            reconciliation.considered
            reconciliation.disposition!(:quarantined, reason: "multiple_videos_per_owner")
          end
          return
        end

        owned.each { |record| transfer_one(record, owner_source_id) }
      end

      def transfer_one(record, owner_source_id)
        reconciliation.considered

        label = Date9ja::Import::VideoModeration.label(record.moderation_status)
        return reconciliation.disposition!(:quarantined, reason: "moderation_unmapped") if label.nil?

        reconciliation.measure!(:"moderation_#{label}")

        profile = resolve_owner(owner_source_id)
        if profile.nil?
          reconciliation.measure!(:owner_not_imported)
          return reconciliation.disposition!(:owner_not_imported, reason: "owner_not_imported")
        end

        attachment_ref = attachment_ref_for(record)
        return reconciliation.disposition!(:destination_failed, reason: "missing_preflight") if attachment_ref.nil?

        object_ref = attachment_ref.media_object_ref
        content_type = object_ref.content_type.to_s
        unless VIDEO_KIND.content_types.include?(content_type)
          return reconciliation.disposition!(:validation_failed, reason: "unsupported_content_type")
        end

        ctx = {
          record:, owner_source_id:, profile:, attachment_ref:, object_ref:,
          content_type:, label:, original_key: expected_final_key(object_ref:, attachment_ref:, content_type:)
        }

        # RESOLVE — authoritative existing-chain check (2B idempotent resume).
        if @stage == :domain
          state = resolve_existing_domain_state(**ctx)
          case state[:kind]
          when :complete then return finish_already_ready(state[:video])
          when :resume_processing then return run_domain_processing(state[:video], ctx)
          when :conflict then return record_binding_conflict(state[:reason])
          end
        end

        locator = @locator.call(object_ref.source_blob_id)
        return reconciliation.disposition!(:source_unavailable, reason: "source_object_missing") if locator.nil?

        pre_existed = ActiveStorage::Blob.exists?(key: ctx[:original_key])
        transfer = run_media_transfer(object_ref:, attachment_ref:, source_key: locator.key)

        unless transfer.ok?
          return record_failure(transfer)
        end

        record_adoption_measures(transfer, pre_existed:)

        if @stage == :domain
          domain_finalize(**ctx.merge(blob: transfer.blob))
        elsif pre_existed
          reconciliation.disposition!(:already_destination_adopted)
        else
          reconciliation.disposition!(:destination_adopted)
        end
      rescue Migration::MediaTransfer::GlobalBlocker, Migration::MediaTransfer::RemoteIOUnderLock
        raise # real bugs / global blockers — never swallow
      rescue StandardError => e
        Rails.logger.warn("[date9ja] video transfer error: #{e.class}")
        reconciliation.measure!(:destination_failures)
        reconciliation.disposition!(:destination_failed, reason: "transfer_error")
      end

      # --- keys / identity -------------------------------------------------

      def expected_final_key(object_ref:, attachment_ref:, content_type:)
        Migration::MediaTransfer::CanonicalKey.final_key(
          canonical_identity(object_ref:, attachment_ref:).with(canonical_content_type: content_type)
        )
      end

      def canonical_identity(object_ref:, attachment_ref:)
        Migration::MediaTransfer::CanonicalKey::Identity.new(
          source_system: SOURCE_SYSTEM, source_blob_id: object_ref.source_blob_id,
          source_attachment_id: attachment_ref.source_attachment_id,
          destination_purpose: DESTINATION_PURPOSE, destination_brand: SOURCE_SYSTEM,
          canonical_content_type: nil
        )
      end

      def derivative_keys(original_key)
        { playback: Media::ObjectKey.profile_video_playback(original_key),
          poster: Media::ObjectKey.profile_video_poster(original_key) }
      end

      # --- Phase A --------------------------------------------------------

      def run_media_transfer(object_ref:, attachment_ref:, source_key:)
        limit = duration_limit_seconds
        gate = lambda do |facts|
          duration = facts.duration_seconds
          next nil if duration.nil? || duration <= limit

          Migration::MediaTransfer::Result.failed(:quarantined, "duration_over_limit", media_facts: facts)
        end

        @media_transfer.call(
          object_ref:, source_reader: @source_reader, source_key:,
          identity: canonical_identity(object_ref:, attachment_ref:),
          dest_service_name: dest_service, media_kind: VIDEO_KIND, media_gate: gate
        )
      end

      def record_adoption_measures(transfer, pre_existed:)
        facts = transfer.media_facts
        if facts&.duration_seconds
          reconciliation.measure!(:duration_derived)
          reconciliation.measure!(:duration_within_limit)
        end
        case transfer.canonical_content_type
        when "video/mp4" then reconciliation.measure!(:content_type_mp4)
        when "video/quicktime" then reconciliation.measure!(:content_type_quicktime)
        end
        reconciliation.measure!(pre_existed ? :destination_uploads_reused : :destination_uploads_created)
      end

      def record_failure(transfer)
        reason = transfer.reason
        case reason
        when "malformed_container" then reconciliation.measure!(:container_invalid)
        when "duration_unreadable" then reconciliation.measure!(:duration_unreadable)
        when "duration_over_limit" then reconciliation.measure!(:duration_over_limit)
        when "source_size_mismatch", "source_checksum_mismatch", "content_type_drift"
          reconciliation.measure!(:source_changed)
        when "remote_orphan"
          reconciliation.measure!(:destination_remote_orphans)
          reconciliation.measure!(:binding_conflicts)
        when "destination_collision"
          reconciliation.measure!(:destination_collisions)
          reconciliation.measure!(:binding_conflicts)
        end

        disposition = MEDIA_DISPOSITION.fetch(transfer.disposition, :destination_failed)
        reconciliation.measure!(:destination_failures) if disposition == :destination_failed
        reconciliation.disposition!(disposition, reason:)
      end

      MEDIA_DISPOSITION = {
        quarantined: :quarantined,
        validation_failed: :validation_failed,
        source_changed: :source_changed,
        source_unavailable: :source_unavailable,
        binding_conflict: :binding_conflict
      }.freeze

      # --- Phase B (domain binding) --------------------------------------

      def domain_finalize(record:, owner_source_id:, profile:, attachment_ref:, object_ref:, content_type:,
        label:, original_key:, blob:)
        moderation = MODERATION_MAP.fetch(label)
        outcome = { disposition: nil }

        Migration::MediaTransfer::LockGuard.hold do
          ProfileVideo.transaction do
            locked_ref = Migration::MediaAttachmentRef.lock.find(attachment_ref.id)
            fresh_owner = load_owner(owner_source_id)

            outcome =
              if locked_ref.media_object_ref_id != object_ref.id
                { disposition: :binding_conflict, reason: "chain_mismatch" }
              elsif fresh_owner.nil? || fresh_owner.id != profile.id
                { disposition: :binding_conflict, reason: "mapping_drift" }
              elsif blob.reload.key != original_key
                { disposition: :binding_conflict, reason: "chain_mismatch" }
              else
                bind_domain(record:, profile: fresh_owner, blob:, moderation:, object_ref:, attachment_ref:, label:)
              end
          rescue ActiveRecord::RecordNotFound
            outcome = { disposition: :binding_conflict, reason: "chain_mismatch" }
          end
        end

        apply_domain_outcome(outcome, record:, profile:, original_key:)
      rescue Profiles::VideoUpload::AlreadyAttached
        record_binding_conflict("conflicting_profile_video")
      rescue Migration::ReferenceMap::ImmutableBinding
        record_binding_conflict("binding_immutable")
      rescue Migration::ReferenceMap::DestinationConflict
        record_binding_conflict("conflicting_binding")
      rescue ActiveRecord::RecordInvalid
        reconciliation.disposition!(:destination_failed, reason: "record_invalid")
      end

      def bind_domain(record:, profile:, blob:, moderation:, object_ref:, attachment_ref:, label:)
        existing = Migration::ReferenceMap.resolve(
          source_system: SOURCE_SYSTEM, source_entity: VIDEO_ENTITY, source_id: record.source_id
        )
        return existing_binding_outcome(existing, profile:, blob:, moderation:) if existing

        if ProfileVideo.kept.exists?(profile:)
          return { disposition: :binding_conflict, reason: "one_video_invariant" }
        end

        video = Profiles::VideoUpload.build_video!(
          profile:, user: profile.user, brand:, blob:,
          status: moderation.fetch(:status), visibility: moderation.fetch(:visibility)
        )
        Migration::ReferenceMap.bind!(
          source_system: SOURCE_SYSTEM, source_entity: VIDEO_ENTITY, source_id: record.source_id,
          destination: video, importer_version: @importer_version, brand:,
          fingerprint: binding_fingerprint(record:, object_ref:, attachment_ref:, label:)
        )
        { disposition: :created, video: }
      end

      # A ProfileVideo -> ReferenceMap binding that appeared/changed between
      # RESOLVE and Phase B. Fail closed unless it is EXACTLY this chain.
      def existing_binding_outcome(existing, profile:, blob:, moderation:)
        video = existing.destination
        unless existing.destination_type == "ProfileVideo" && video&.id.present?
          return { disposition: :binding_conflict, reason: "chain_mismatch" }
        end
        if video.user_id != profile.user_id || video.profile_id != profile.id || video.brand_id != brand.id
          return { disposition: :binding_conflict, reason: "mapping_drift" }
        end

        exact = video.kept? && video.video.attached? && video.video.blob.key == blob.key &&
          video.status == moderation.fetch(:status).to_s &&
          video.visibility == moderation.fetch(:visibility).to_s
        exact ? { disposition: :bound, video: } : { disposition: :binding_conflict, reason: "chain_mismatch" }
      end

      def apply_domain_outcome(outcome, record:, profile:, original_key:)
        case outcome[:disposition]
        when :created
          reconciliation.measure!(:profile_videos_created)
          reconciliation.measure!(:reference_map_bindings_created)
          run_domain_processing(outcome[:video], { original_key:, record:, profile: })
        when :bound
          reconciliation.measure!(:profile_videos_reused)
          reconciliation.measure!(:reference_map_bindings_reused)
          run_domain_processing(outcome[:video], { original_key:, record:, profile: })
        when :binding_conflict
          record_binding_conflict(outcome[:reason])
        else
          reconciliation.disposition!(:destination_failed, reason: "record_invalid")
        end
      end

      # --- Phase C (processing + derivative validation) -----------------

      def run_domain_processing(video, ctx)
        keys = derivative_keys(ctx.fetch(:original_key))
        reconciliation.measure!(:processing_attempts)

        if video.processing_ready? && derivatives_valid?(video, keys)
          return finish_already_ready(video)
        end

        reconciliation.measure!(:processing_stale_reclaims) if video.processing_claim_stale?

        run_processing_job(video.id)
        settle_processing(video.id, keys)
      end

      # The job records its own terminal/failed state (including
      # `derivative_conflict` / candidate-validation failure — review Finding 1);
      # a re-raised `TransientError` on retry exhaustion is expected and is not a
      # migration error. `settle_processing` reads the persisted state.
      def run_processing_job(video_id)
        if @processing == :inline
          Media::ProcessProfileVideoJob.perform_now(video_id)
        else
          Media::ProcessProfileVideoJob.perform_later(video_id)
          drain!(video_id)
        end
      rescue Media::ProcessProfileVideoJob::TransientError
        nil
      end

      def settle_processing(video_id, keys)
        video = ProfileVideo.find_by(id: video_id)
        if video&.processing_ready? && derivatives_valid?(video, keys)
          reconciliation.measure!(:processing_succeeded)
          reconciliation.measure!(:playback_validated)
          reconciliation.measure!(:poster_validated)
          ensure_raw_purge_scheduled(video)
          reconciliation.measure!(:originals_purged)
          reconciliation.measure!(:ready)
          reconciliation.disposition!(:ready)
        elsif video&.processing_ready?
          # processing "succeeded" but the actual derivatives do not validate.
          reconciliation.disposition!(:derivative_validation_failed, reason: "playback_invalid")
        elsif video&.processing_failed?
          reconciliation.measure!(:processing_failures)
          reconciliation.disposition!(:processing_failed, reason: "processing_job_failed")
        else
          reconciliation.measure!(:processing_failures)
          reconciliation.disposition!(:processing_failed, reason: "processing_drain_timeout")
        end
      end

      def finish_already_ready(video)
        keys = derivative_keys(video_original_key(video))
        unless derivatives_valid?(video, keys)
          return record_binding_conflict("playback_invalid")
        end

        reconciliation.measure!(:already_ready)
        ensure_raw_purge_scheduled(video)
        reconciliation.disposition!(:already_ready)
      end

      def video_original_key(video)
        return video.video.blob.key if video.video.attached?

        video.metadata["raw_object_key"].to_s
      end

      # The existing runtime purge behaviour (Media::ProcessProfileVideoJob) fires
      # `video.purge_later` once the video reaches ready. This just guarantees the
      # schedule survived (e.g. the job's post-commit enqueue lost the raw
      # reference) — it never purges before ready.
      def ensure_raw_purge_scheduled(video)
        video.reload
        video.video.purge_later if video.processing_ready? && video.video.attached?
      end

      # Bounded remote validation of the EXACT accepted deterministic playback +
      # poster pair. Runs OUTSIDE all DB locks (LockGuard asserts this).
      def derivatives_valid?(video, keys)
        Migration::MediaTransfer.valid_accepted_playback?(
          video:, expected_playback_key: keys[:playback], expected_poster_key: keys[:poster],
          expected_service: dest_service
        )
      end

      def drain!(id, timeout: @drain_timeout)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout.to_f
        loop do
          video = ProfileVideo.find_by(id:)
          return if video.nil? || video.processing_ready? || video.processing_failed?
          return if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

          sleep 0.05
        end
      end

      # --- RESOLVE (2B idempotent existing-chain check) ------------------

      def resolve_existing_domain_state(record:, profile:, attachment_ref:, object_ref:, content_type:,
        label:, original_key:, owner_source_id:)
        existing = Migration::ReferenceMap.resolve(
          source_system: SOURCE_SYSTEM, source_entity: VIDEO_ENTITY, source_id: record.source_id
        )
        return { kind: :absent } if existing.nil?
        return { kind: :conflict, reason: "chain_mismatch" } unless existing.destination_type == "ProfileVideo"

        video = existing.destination
        return { kind: :conflict, reason: "chain_mismatch" } if video.nil? || !video.kept?
        return { kind: :conflict, reason: "mapping_drift" } unless video.user_id == profile.user_id && video.profile_id == profile.id
        return { kind: :conflict, reason: "chain_mismatch" } unless video.brand_id == brand.id

        moderation = MODERATION_MAP.fetch(label)
        unless video.status == moderation.fetch(:status).to_s && video.visibility == moderation.fetch(:visibility).to_s
          return { kind: :conflict, reason: "chain_mismatch" }
        end

        keys = derivative_keys(original_key)
        classify_existing_video(video, original_key:, keys:)
      end

      def classify_existing_video(video, original_key:, keys:)
        if video.video.attached?
          return { kind: :conflict, reason: "chain_mismatch" } unless video.video.blob.key == original_key

          if video.processing_ready?
            derivatives_valid?(video, keys) ? { kind: :complete, video: } : { kind: :conflict, reason: "playback_invalid" }
          else
            { kind: :resume_processing, video: }
          end
        elsif video.processing_ready? && derivatives_valid?(video, keys)
          { kind: :complete, video: } # raw legitimately purged after ready
        else
          { kind: :conflict, reason: "chain_mismatch" } # raw gone, not ready -> corrupt terminal state
        end
      end

      # --- helpers -------------------------------------------------------

      def record_binding_conflict(reason)
        reconciliation.measure!(:binding_conflicts)
        reconciliation.disposition!(:binding_conflict, reason:)
      end

      def binding_fingerprint(record:, object_ref:, attachment_ref:, label:)
        Digest::SHA256.hexdigest([
          record.source_id, label, object_ref.source_blob_id, attachment_ref.source_attachment_id
        ].map(&:to_s).join("|"))[0, 32]
      end

      def attachment_ref_for(record)
        attachment = record.video_attachment
        return nil if attachment.nil?

        Migration::MediaAttachmentRef.find_by(
          source_system: SOURCE_SYSTEM, source_attachment_id: attachment.source_id
        )
      end

      def resolve_owner(owner_source_id)
        @owner_cache.fetch(owner_source_id) { @owner_cache[owner_source_id] = load_owner(owner_source_id) }
      end

      def load_owner(owner_source_id)
        reference = Migration::ReferenceMap.resolve(
          source_system: SOURCE_SYSTEM, source_entity: OWNER_ENTITY, source_id: owner_source_id
        )
        return nil if reference.nil? || reference.destination_type != "Profile" || reference.brand_id != brand.id

        destination = reference.destination
        destination if destination && destination.brand_id == brand.id
      end
    end
  end
end
