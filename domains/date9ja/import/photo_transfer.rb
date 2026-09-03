# frozen_string_literal: true

module Date9ja
  module Import
    # WAVE A — profile-photo BYTE TRANSFER (pass 2). Governed by ADR 0028 /
    # MEDIA-TRANSFER.md. Consumes the pass-1 preflight graph
    # (Migration::MediaObjectRef / MediaAttachmentRef) and turns it into real
    # D8N ProfilePhoto media.
    #
    #   per owner, photos in PhotoOrderPlan order:
    #     RESOLVE  authoritative deterministic-chain check of any prior transfer
    #     PHASE A  Migration::MediaTransfer.call — verify source bytes,
    #              adopt-or-upload the destination blob, re-verify the remote
    #              object. NO DB lock / transaction held for any remote work.
    #     PHASE B  short finalization transaction: SELECT MediaAttachmentRef FOR
    #              UPDATE ; re-resolve owner authoritatively ; build_photo! ;
    #              ReferenceMap.bind!
    #     PHASE C  after commit: process (inline perform_now, or enqueue + bounded
    #              drain) — `transferred` only after processing_ready with a
    #              validated deterministic display derivative.
    class PhotoTransfer
      SOURCE_SYSTEM = "date9ja"
      OWNER_ENTITY = "profile"
      PHOTO_ENTITY = "photo"
      ATTACHMENT_NAME = "image"
      IMPORTER_VERSION = "date9ja-photo-transfer-v1"
      DESTINATION_PURPOSE = "profile_photo_original"
      EXPECTED_SOURCE_SERVICE = "cloudflare"
      DEFAULT_DRAIN_TIMEOUT = 30.seconds

      Result = Data.define(:reconciliation)

      class WrongBrand < StandardError; end

      MODERATION_MAP = {
        "pending" => { status: :pending_review, visibility: :visible },
        "approved" => { status: :approved, visibility: :visible },
        "rejected" => { status: :rejected, visibility: :hidden }
      }.freeze

      def self.call(...) = new(...).call

      def initialize(brand:, source:, locator:, source_reader:, media_transfer: Migration::MediaTransfer,
        importer_version: IMPORTER_VERSION, processing: :inline, drain_timeout: DEFAULT_DRAIN_TIMEOUT)
        @brand = brand
        @source = source
        @locator = locator
        @source_reader = source_reader
        @media_transfer = media_transfer
        @importer_version = importer_version
        @processing = processing
        @drain_timeout = drain_timeout
        @reconciliation = PhotoTransferReconciliation.new
      end

      def call
        assert_brand!
        records = @source.to_a
        assert_single_source_service!(records)
        @reconciliation.measure!(:total_source_photos, records.size, mode: :set)

        records.group_by(&:owner_source_id).each do |owner_source_id, owned|
          transfer_owner(owner_source_id, owned)
        end

        Result.new(@reconciliation)
      end

      private

      attr_reader :brand, :reconciliation

      def dest_service = Media::StorageResolver.service_name(brand:).to_s

      def assert_brand!
        return if brand&.slug == SOURCE_SYSTEM && brand.active? && brand.deleted_at.nil?

        raise WrongBrand, "photo transfer requires the active date9ja brand"
      end

      # Global blocker: any photo blob on a service other than `cloudflare`.
      def assert_single_source_service!(records)
        blob_ids = records.filter_map { |r| r.image_attachment&.blob&.source_id }
        offenders = blob_ids.filter_map { |bid| @locator.call(bid)&.service_name }
          .reject { |name| name == EXPECTED_SOURCE_SERVICE }.uniq
        return if offenders.empty?

        raise Migration::MediaTransfer::GlobalBlocker,
          "date9ja photo blobs on unexpected storage service(s): #{offenders.sort.join(', ')}"
      end

      def transfer_owner(owner_source_id, owned)
        reconciliation.measure!(:owners_ordered)

        begin
          plan = PhotoOrderPlan.call(owned)
        rescue PhotoOrderPlan::MultiplePrimary
          reconciliation.measure!(:owners_multiple_primary_quarantined)
          reconciliation.measure!(:owners_flagged_for_review)
          owned.each do
            reconciliation.considered
            reconciliation.disposition!(:quarantined, reason: "multiple_primary")
          end
          return
        end

        primaries = owned.count(&:is_primary)
        reconciliation.measure!(primaries == 1 ? :owners_one_primary : :owners_zero_primary)

        plan.each { |entry| transfer_one(entry, owner_source_id) }
      end

      def transfer_one(entry, owner_source_id)
        reconciliation.considered
        photo = entry.photo

        label = Date9ja::Import::PhotoModeration.label(photo.moderation_status)
        return reconciliation.disposition!(:quarantined, reason: "moderation_unmapped") if label.nil?

        reconciliation.measure!(:"moderation_#{label}")
        moderation = MODERATION_MAP.fetch(label)

        profile = resolve_owner(owner_source_id)
        return reconciliation.disposition!(:owner_not_imported, reason: "owner_not_imported") if profile.nil?

        attachment_ref = attachment_ref_for(photo)
        return reconciliation.disposition!(:destination_failed, reason: "missing_preflight") if attachment_ref.nil?

        object_ref = attachment_ref.media_object_ref
        keys = expected_keys(object_ref:, attachment_ref:)

        # RESOLVE — authoritative deterministic-chain check of any prior transfer.
        state = resolve_existing_state(photo:, profile:, entry:, moderation:, keys:)
        case state[:kind]
        when :complete
          return reconciliation.disposition!(:already_transferred)
        when :conflict
          return record_binding_conflict(state[:reason])
        when :resume_processing
          # built + bound already; only processing is incomplete. Do NOT re-run
          # Phase A (would orphan a blob) — just (re)process.
          return run_processing(state[:photo].id, keys:)
        end

        locator = @locator.call(object_ref.source_blob_id)
        return reconciliation.disposition!(:source_unavailable, reason: "source_object_missing") if locator.nil?

        transfer = run_media_transfer(object_ref:, source_key: locator.key, attachment_ref:)
        unless transfer.ok?
          object_ref.mark_transfer_failed!(transfer.reason) if object_ref.transfer_not_started?
          count_transfer_failure(transfer)
          return reconciliation.disposition!(transfer.disposition, reason: transfer.reason)
        end

        finalize_transfer(photo:, owner_source_id:, resolved_profile: profile, entry:, attachment_ref:,
          object_ref:, transfer:, moderation:, keys:)
      rescue Migration::MediaTransfer::GlobalBlocker
        raise
      rescue Migration::MediaTransfer::RemoteIOUnderLock
        raise # a real bug — never swallow
      rescue StandardError => e
        Rails.logger.warn("[date9ja] photo transfer error: #{e.class}")
        reconciliation.disposition!(:destination_failed, reason: "transfer_error")
      end

      def run_media_transfer(object_ref:, source_key:, attachment_ref:)
        identity = Migration::MediaTransfer::CanonicalKey::Identity.new(
          source_system: SOURCE_SYSTEM, source_blob_id: object_ref.source_blob_id,
          source_attachment_id: attachment_ref.source_attachment_id,
          destination_purpose: DESTINATION_PURPOSE, destination_brand: SOURCE_SYSTEM,
          canonical_content_type: nil
        )
        @media_transfer.call(
          object_ref:, source_reader: @source_reader, source_key:, identity:, dest_service_name: dest_service
        )
      end

      def count_transfer_failure(transfer)
        case transfer.reason
        when "remote_orphan" then reconciliation.measure!(:destination_remote_orphans)
        when "destination_collision" then reconciliation.measure!(:destination_collisions)
        end
        reconciliation.measure!(:binding_conflicts) if transfer.disposition == :binding_conflict
      end

      # The exact accepted deterministic keys. canonical_content_type is the
      # PREFLIGHTED type (a verified divergence is source_changed in Phase A, so a
      # bound photo's key always reflects object_ref.content_type).
      def expected_keys(object_ref:, attachment_ref:)
        ct = object_ref.content_type.to_s
        return { content_type: ct, original: nil, display: nil } unless Migration::MediaTransfer::ALLOWED_CONTENT_TYPES.include?(ct)

        identity = Migration::MediaTransfer::CanonicalKey::Identity.new(
          source_system: SOURCE_SYSTEM, source_blob_id: object_ref.source_blob_id,
          source_attachment_id: attachment_ref.source_attachment_id,
          destination_purpose: DESTINATION_PURPOSE, destination_brand: SOURCE_SYSTEM,
          canonical_content_type: ct
        )
        original = Migration::MediaTransfer::CanonicalKey.final_key(identity)
        { content_type: ct, original:, display: Migration::MediaTransfer::CanonicalKey.display_key(original) }
      end

      # Complete authoritative chain validation (review Finding 1). NO prefix
      # matching. `already_transferred` only when EVERY link proves this exact
      # source attachment already completed the accepted migration.
      def resolve_existing_state(photo:, profile:, entry:, moderation:, keys:)
        existing = Migration::ReferenceMap.resolve(
          source_system: SOURCE_SYSTEM, source_entity: PHOTO_ENTITY, source_id: photo.source_id
        )
        return { kind: :absent } if existing.nil?
        return { kind: :conflict, reason: "chain_mismatch" } unless existing.destination_type == "ProfilePhoto"

        destination = existing.destination
        return { kind: :conflict, reason: "chain_mismatch" } if destination.nil? || !destination.kept?
        return { kind: :conflict, reason: "mapping_drift" } unless owner_matches?(destination, profile)
        return { kind: :conflict, reason: "chain_mismatch" } if keys[:original].nil?

        plan_ok = destination.brand_id == brand.id &&
          destination.position == entry.destination_position &&
          destination.status == moderation.fetch(:status).to_s &&
          destination.visibility == moderation.fetch(:visibility).to_s
        return { kind: :conflict, reason: "chain_mismatch" } unless plan_ok

        classify_destination_media(destination, keys)
      end

      def classify_destination_media(destination, keys)
        if destination.image.attached?
          return { kind: :conflict, reason: "chain_mismatch" } unless destination.image.blob.key == keys[:original]

          if destination.processing_ready?
            if accepted_display?(destination, keys)
              { kind: :complete }
            else
              { kind: :conflict, reason: "chain_mismatch" }
            end
          else
            # built + bound, raw still present, processing not done -> resume.
            { kind: :resume_processing, photo: destination }
          end
        elsif destination.processing_ready? && accepted_display?(destination, keys)
          { kind: :complete } # raw legitimately purged after processing
        else
          # raw purged but no valid ready display -> corrupt terminal state.
          { kind: :conflict, reason: "chain_mismatch" }
        end
      end

      def accepted_display?(destination, keys)
        Migration::MediaTransfer.valid_accepted_display?(
          photo: destination, expected_display_key: keys[:display], expected_service: dest_service
        )
      end

      def owner_matches?(destination, profile)
        profile && destination.user_id == profile.user_id && destination.profile_id == profile.id
      end

      # PHASE B — short finalization transaction (LockGuard-held) + PHASE C.
      def finalize_transfer(photo:, owner_source_id:, resolved_profile:, entry:, attachment_ref:, object_ref:,
        transfer:, moderation:, keys:)
        blob = transfer.blob
        outcome = { disposition: nil }

        Migration::MediaTransfer::LockGuard.hold do
          ProfilePhoto.transaction do
            locked_ref = Migration::MediaAttachmentRef.lock.find(attachment_ref.id)
            profile = reresolve_owner_locked(owner_source_id)

            outcome =
              if locked_ref.media_object_ref_id != object_ref.id
                { disposition: :binding_conflict, reason: "chain_mismatch" }
              elsif profile.nil? || profile.id != resolved_profile.id
                # Owner mapping changed between RESOLVE and Phase B — never
                # silently build for a different owner (review Finding 1).
                { disposition: :binding_conflict, reason: "mapping_drift" }
              elsif blob.key != keys[:original]
                { disposition: :binding_conflict, reason: "chain_mismatch" }
              else
                finalize_binding(photo:, profile:, entry:, moderation:, blob:, object_ref:, attachment_ref:)
              end
          end
        end

        apply_finalize_outcome(outcome, keys:)
      rescue Profiles::PhotoUpload::AlreadyAttached
        record_binding_conflict("chain_mismatch")
      rescue Profiles::PhotoUpload::LimitReached
        reconciliation.measure!(:owners_flagged_for_review)
        reconciliation.disposition!(:quarantined, reason: "capacity_exceeded")
      rescue Migration::ReferenceMap::ImmutableBinding
        record_binding_conflict("binding_immutable")
      rescue Migration::ReferenceMap::DestinationConflict
        record_binding_conflict("chain_mismatch")
      rescue ActiveRecord::RecordInvalid
        reconciliation.disposition!(:destination_failed, reason: "record_invalid")
      end

      def finalize_binding(photo:, profile:, entry:, moderation:, blob:, object_ref:, attachment_ref:)
        existing = Migration::ReferenceMap.resolve(
          source_system: SOURCE_SYSTEM, source_entity: PHOTO_ENTITY, source_id: photo.source_id
        )
        if existing
          # `profile` here is the CURRENT re-resolved owner (finalize_transfer
          # already proved profile.id == resolved_profile.id under the lock). Any
          # existing Photo -> ProfilePhoto destination must belong to THIS exact
          # profile — same user + WRONG profile is mapping_drift, never
          # already_transferred, never a silent reparent (review Finding 2).
          return existing_binding_outcome(existing, profile:, entry:, moderation:, blob:)
        end

        record = Profiles::PhotoUpload.build_photo!(
          profile:, user: profile.user, brand:, blob:,
          position: entry.destination_position,
          status: moderation.fetch(:status), visibility: moderation.fetch(:visibility)
        )
        Migration::ReferenceMap.bind!(
          source_system: SOURCE_SYSTEM, source_entity: PHOTO_ENTITY, source_id: photo.source_id,
          destination: record, importer_version: @importer_version, brand:,
          fingerprint: binding_fingerprint(photo:, object_ref:, attachment_ref:)
        )
        object_ref.mark_transferred!
        { disposition: :created, photo_record: record }
      end

      # Fail-closed classification of an existing Photo -> ProfilePhoto
      # ReferenceMap destination found DURING Phase B (the race Codex described:
      # a binding appears/changes between RESOLVE and finalization).
      def existing_binding_outcome(existing, profile:, entry:, moderation:, blob:)
        dest = existing.destination
        unless existing.destination_type == "ProfilePhoto" && dest&.id.present?
          return { disposition: :binding_conflict, reason: "chain_mismatch" }
        end

        wrong_owner = dest.user_id != profile.user_id ||
          dest.profile_id != profile.id ||
          dest.brand_id != brand.id
        return { disposition: :binding_conflict, reason: "mapping_drift" } if wrong_owner

        exact = dest.kept? &&
          dest.image.attached? &&
          dest.image.blob.key == blob.key &&
          dest.position == entry.destination_position &&
          dest.status == moderation.fetch(:status).to_s &&
          dest.visibility == moderation.fetch(:visibility).to_s
        return { disposition: :already_transferred } if exact

        { disposition: :binding_conflict, reason: "chain_mismatch" }
      end

      def apply_finalize_outcome(outcome, keys:)
        case outcome[:disposition]
        when :already_transferred
          reconciliation.disposition!(:already_transferred)
        when :binding_conflict
          record_binding_conflict(outcome[:reason])
        when :created
          reconciliation.measure!(:destination_uploads_created)
          reconciliation.measure!(:profile_photos_created)
          reconciliation.measure!(:reference_map_bindings_created)
          process_after_commit(outcome[:photo_record], keys:)
        else
          reconciliation.disposition!(:destination_failed, reason: "transfer_error")
        end
      end

      # PHASE C — after commit. `transferred` requires processing_ready + a
      # validated deterministic display derivative (review Finding 3).
      def process_after_commit(record, keys:)
        run_processing(record.id, keys:)
      end

      def run_processing(photo_id, keys:)
        reconciliation.measure!(:processing_enqueued)
        if @processing == :inline
          Media::ProcessProfilePhotoJob.perform_now(photo_id)
        else
          Media::ProcessProfilePhotoJob.perform_later(photo_id)
          drain!(photo_id)
        end
        settle_processing(ProfilePhoto.find(photo_id), keys:)
      end

      def drain!(id, timeout: @drain_timeout)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout.to_f
        loop do
          photo = ProfilePhoto.find_by(id:)
          return if photo.nil? || photo.processing_ready? || photo.processing_failed?
          return if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

          sleep 0.05
        end
      end

      def settle_processing(photo, keys:)
        photo = ProfilePhoto.find_by(id: photo.id)
        if photo&.processing_ready? && accepted_display?(photo, keys)
          reconciliation.measure!(:processing_succeeded)
          reconciliation.disposition!(:transferred)
        elsif photo&.processing_failed?
          reconciliation.measure!(:processing_failed)
          reconciliation.disposition!(:processing_failed, reason: "processing_failed")
        else
          reconciliation.measure!(:processing_failed)
          reconciliation.disposition!(:processing_failed, reason: "processing_drain_timeout")
        end
      end

      def record_binding_conflict(reason)
        reconciliation.measure!(:binding_conflicts)
        reconciliation.measure!(:mapping_drift) if reason == "mapping_drift"
        reconciliation.disposition!(:binding_conflict, reason:)
      end

      def binding_fingerprint(photo:, object_ref:, attachment_ref:)
        Digest::SHA256.hexdigest([
          photo.position, photo.is_primary, photo.moderation_status,
          object_ref.source_blob_id, attachment_ref.source_attachment_id
        ].map(&:to_s).join("|"))[0, 32]
      end

      def attachment_ref_for(photo)
        attachment = photo.image_attachment
        return nil if attachment.nil?

        Migration::MediaAttachmentRef.find_by(
          source_system: SOURCE_SYSTEM, source_attachment_id: attachment.source_id
        )
      end

      # RESOLVE-phase owner read (cached, no lock).
      def resolve_owner(owner_source_id)
        @owner_cache ||= {}
        @owner_cache.fetch(owner_source_id) { @owner_cache[owner_source_id] = load_owner(owner_source_id) }
      end

      # PHASE B owner read — authoritative, uncached, no stale pre-Phase-A value.
      def reresolve_owner_locked(owner_source_id)
        load_owner(owner_source_id)
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
