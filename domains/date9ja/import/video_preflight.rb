# frozen_string_literal: true

module Date9ja
  module Import
    # WAVE A — profile-video MEDIA PREFLIGHT (pass 1). The video analogue of
    # Date9ja::Import::PhotoImport; it reuses the SAME generic migration-media
    # spine and adds no new framework.
    #
    #   Date9ja::Snapshot::VideoSource
    #     -> Migration::MediaObjectRef      (one per source blob, integrity metadata)
    #     -> Migration::MediaAttachmentRef  (one per source attachment/use)
    #     -> deterministic, PII-free VideoPreflightReconciliation
    #
    # PASS 1 does NOT: copy or open blob bytes, create ProfileVideo, create D8N
    # Active Storage records, enqueue processing, generate playback/poster
    # derivatives, bind Migration::ReferenceMap (that is pass 2), or apply any
    # visibility policy. It records and measures the source media graph and
    # transfer-readiness only.
    class VideoPreflight
      SOURCE_SYSTEM = "date9ja"
      OWNER_ENTITY = "profile"
      SOURCE_RECORD_ENTITY = "profile_video"
      ATTACHMENT_NAME = "video"
      IMPORTER_VERSION = "date9ja-video-preflight-v1"

      # Reuse the shared model/policy contract — never a second hard-coded list.
      SUPPORTED_CONTENT_TYPES = ProfileVideo::ALLOWED_CONTENT_TYPES

      Result = Data.define(:reconciliation)

      class WrongBrand < StandardError; end
      class PreflightConflict < StandardError
        attr_reader :reason

        def initialize(reason)
          @reason = reason
          super(reason)
        end
      end

      def self.call(...) = new(...).call

      def initialize(brand:, source:, importer_version: IMPORTER_VERSION)
        @brand = brand
        @source = source
        @importer_version = importer_version
        @reconciliation = VideoPreflightReconciliation.new
        @owner_cache = {}
      end

      def call
        assert_brand!

        records = @source.to_a
        @multi_owner_ids = owner_ids_with_multiple_videos(records)
        measure_owner_aggregates(records)

        records.each do |record|
          @reconciliation.considered
          preflight_one(record)
        end

        record_blob_reuse
        Result.new(@reconciliation)
      end

      private

      attr_reader :brand, :reconciliation

      def assert_brand!
        return if brand&.slug == SOURCE_SYSTEM && brand.active? && brand.deleted_at.nil?

        raise WrongBrand, "video preflight requires the active date9ja brand"
      end

      def duration_limit_seconds
        @duration_limit_seconds ||= Media::VideoPolicy.max_duration_seconds(brand:)
      rescue Media::VideoPolicy::NotConfigured
        Media::VideoPolicy::DEFAULT_MAX_DURATION_SECONDS
      end

      def owner_ids_with_multiple_videos(records)
        records.group_by(&:owner_source_id).select { |_, owned| owned.size > 1 }.keys.to_set
      end

      # ---- aggregate measures (never normalize anomalies, only count) ---------

      def measure_owner_aggregates(records)
        reconciliation.measure!(:total_source_videos, records.size, mode: :set)
        reconciliation.measure!(:max_duration_limit_seconds, duration_limit_seconds, mode: :set)

        records.each do |record|
          label = VideoModeration.label(record.moderation_status)
          reconciliation.measure!(:"moderation_#{label}") if label
          measure_duration(record.duration_seconds)
        end

        by_owner = records.group_by(&:owner_source_id)
        reconciliation.measure!(:owners_total, by_owner.size, mode: :set)

        by_owner.each do |owner_source_id, owned|
          case owned.size
          when 1 then reconciliation.measure!(:owners_with_one_video)
          else reconciliation.measure!(:owners_with_multiple_videos)
          end

          profile = resolve_owner(owner_source_id)
          reconciliation.measure!(:owners_suspended) if profile&.status == "suspended"
        end
      end

      # `duration_seconds` is legacy-nullable and was client-trusted in Date9ja —
      # every source row in the verified snapshot is NULL. Classify, never reject.
      def measure_duration(raw)
        if raw.nil? || raw.to_s.strip.empty?
          return reconciliation.measure!(:duration_missing)
        end

        seconds = Integer(raw, exception: false)
        if seconds.nil? || seconds <= 0
          reconciliation.measure!(:duration_invalid)
        else
          reconciliation.measure!(:duration_present)
          if seconds <= duration_limit_seconds
            reconciliation.measure!(:duration_within_limit)
          else
            reconciliation.measure!(:duration_over_limit)
          end
        end
      end

      # ---- per-video preflight ---------------------------------------------

      def preflight_one(record)
        @current_created = Hash.new(0)
        ActiveRecord::Base.transaction(requires_new: true) do
          preflight_one_in_transaction(record)
        end
        reconciliation.created!(**@current_created)
      rescue PreflightConflict => error
        reconciliation.measure!(:binding_conflicts)
        reconciliation.disposition!(:failed, reason: error.reason)
      rescue StandardError
        # Keep one unexpected malformed/DB row from aborting the complete source
        # census. The transaction rolls back any partial ref writes and the
        # reconciliation remains PII-free.
        reconciliation.disposition!(:failed, reason: "preflight_error")
      ensure
        @current_created = nil
      end

      def preflight_one_in_transaction(record)
        label = VideoModeration.label(record.moderation_status)
        if label.nil?
          reconciliation.measure!(:malformed_moderation_values)
          return reconciliation.disposition!(:malformed, reason: "moderation_unmapped")
        end

        # Owner-level structural ambiguity: D8N permits one live ProfileVideo per
        # profile. Never arbitrarily pick — fail closed for the whole owner.
        if @multi_owner_ids.include?(record.owner_source_id)
          return reconciliation.disposition!(:failed, reason: "multiple_videos_per_owner")
        end

        attachments = record.attachments
        if attachments.empty?
          reconciliation.measure!(:missing_attachments)
          return reconciliation.disposition!(:unavailable, reason: "missing_attachment")
        end
        if attachments.size > 1
          reconciliation.measure!(:duplicate_attachments)
          return reconciliation.disposition!(:failed, reason: "duplicate_attachment")
        end

        attachment = attachments.first
        blob = attachment.blob
        if blob.nil?
          reconciliation.measure!(:missing_blobs)
          return reconciliation.disposition!(:unavailable, reason: "missing_blob")
        end

        content_type = blob.content_type.to_s.downcase.strip
        byte_size = Integer(blob.byte_size, exception: false)
        checksum = blob.checksum.to_s

        failure = classify_blob(content_type:, byte_size:, checksum:)
        if owner_binding_conflict?(record.owner_source_id)
          return reconciliation.disposition!(:failed, reason: "owner_binding_conflict")
        end

        owner = resolve_owner(record.owner_source_id)
        reconciliation.note!("source_suspended_owner") if owner&.status == "suspended"

        object_ref, object_state = preflight_object(blob:, checksum:, byte_size:, content_type:, failure:)
        return if object_ref.nil? # drift already recorded

        attachment_state = record_attachment(attachment:, record:, object_ref:, owner:, failure:)
        return if attachment_state.nil?

        finalize_disposition(failure:, owner:, object_state:, attachment_state:)
      end

      def classify_blob(content_type:, byte_size:, checksum:)
        if byte_size.nil? || byte_size <= 0 || checksum.empty?
          reconciliation.measure!(:checksum_size_inconsistencies)
          "checksum_size_inconsistent"
        elsif !SUPPORTED_CONTENT_TYPES.include?(content_type)
          reconciliation.measure!(:unsupported_content_types)
          "unsupported_content_type"
        end
      end

      def preflight_object(blob:, checksum:, byte_size:, content_type:, failure:)
        ref, state = Migration::MediaObjectRef.preflight!(
          source_system: SOURCE_SYSTEM,
          source_blob_id: blob.source_id,
          checksum: checksum.presence,
          byte_size: byte_size&.positive? ? byte_size : nil,
          content_type: content_type.presence,
          importer_version: @importer_version,
          preflight_state: (failure ? :failed : :preflighted),
          failure_code: failure
        )
        @current_created[:media_object_refs_created] += 1 if state == :created
        [ ref, state ]
      rescue Migration::MediaObjectRef::Drift
        raise PreflightConflict, "blob_metadata_drift"
      end

      def record_attachment(attachment:, record:, object_ref:, owner:, failure:)
        state =
          if failure then :failed
          elsif owner.nil? then :owner_not_imported
          else :preflighted
          end

        ref, resolved_state = Migration::MediaAttachmentRef.record!(
          source_system: SOURCE_SYSTEM,
          source_attachment_id: attachment.source_id,
          media_object_ref: object_ref,
          source_record_entity: SOURCE_RECORD_ENTITY,
          source_record_id: record.source_id,
          attachment_name: ATTACHMENT_NAME,
          importer_version: @importer_version,
          preflight_state: state,
          failure_code: failure
        )
        @current_created[:media_attachment_refs_created] += 1 if resolved_state == :created
        [ ref, resolved_state ]
      rescue Migration::MediaAttachmentRef::Drift
        raise PreflightConflict, "attachment_drift"
      end

      def finalize_disposition(failure:, owner:, object_state:, attachment_state:)
        ref, state = attachment_state
        if failure
          reconciliation.disposition!(:failed, reason: failure)
        elsif owner.nil?
          reconciliation.measure!(:owner_not_imported)
          reconciliation.disposition!(:owner_not_imported, reason: "owner_not_imported")
        elsif object_state == :unchanged && state == :unchanged && ref.preflight_preflighted?
          reconciliation.disposition!(:already_preflighted)
        else
          reconciliation.disposition!(:preflighted)
        end
      end

      def record_blob_reuse
        reuse = Migration::MediaAttachmentRef.where(source_system: SOURCE_SYSTEM)
          .group(:media_object_ref_id).count.count { |_, n| n > 1 }
        reconciliation.measure!(:blob_reuse_objects, reuse, mode: :set)
      end

      def resolve_owner(owner_source_id)
        status, profile = owner_resolution(owner_source_id)
        status == :resolved ? profile : nil
      end

      def owner_binding_conflict?(owner_source_id)
        owner_resolution(owner_source_id).first == :conflict
      end

      def owner_resolution(owner_source_id)
        @owner_cache.fetch(owner_source_id) do
          reference = Migration::ReferenceMap.resolve(
            source_system: SOURCE_SYSTEM, source_entity: OWNER_ENTITY, source_id: owner_source_id
          )
          result =
            if reference.nil?
              [ :missing, nil ]
            elsif reference.destination_type != "Profile" || reference.brand_id != brand.id
              [ :conflict, nil ]
            elsif (profile = reference.destination).nil? || profile.brand_id != brand.id
              [ :missing, nil ]
            else
              [ :resolved, profile ]
            end
          @owner_cache[owner_source_id] = result
        end
      end
    end
  end
end
