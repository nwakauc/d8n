# frozen_string_literal: true

require "test_helper"

module Date9ja
  module Import
    class VideoPreflightTest < ActiveSupport::TestCase
      include ActiveJob::TestHelper

      setup do
        @brand = Brand.create!(
          slug: "date9ja", name: "Date9ja", status: :active,
          auth_methods: %w[email_password phone_password]
        )
      end

      # --- helpers -----------------------------------------------------------

      def import_owner(user_id, status: :active)
        user = User.create!
        membership = BrandMembership.create!(user: user, brand: @brand, status: status)
        profile = Profile.create!(
          user: user, brand: @brand, brand_membership: membership,
          display_name: "P#{user_id}", birthdate: 27.years.ago.to_date, gender: "woman",
          status: (status == :suspended ? :suspended : :draft)
        )
        Migration::ReferenceMap.bind!(
          source_system: "date9ja", source_entity: "profile", source_id: user_id.to_s,
          destination: profile, importer_version: "date9ja-identity-v1", brand: @brand
        )
        profile
      end

      def video_row(id:, user_id: 1, **overrides)
        {
          "id" => id, "user_id" => user_id, "duration_seconds" => nil, "moderation_status" => 0,
          "created_at" => Time.utc(2024, 1, 1), "reviewed_at" => nil
        }.merge(overrides.transform_keys(&:to_s))
      end

      def attachment_row(id:, record_id:, blob_id:, name: "video", record_type: "ProfileVideo")
        { "id" => id, "name" => name, "record_type" => record_type, "record_id" => record_id, "blob_id" => blob_id }
      end

      def blob_row(id:, byte_size: 8_000_000, checksum: "chk-#{id}", content_type: "video/mp4")
        { "id" => id, "byte_size" => byte_size, "checksum" => checksum, "content_type" => content_type }
      end

      def bundle(video_id:, user_id: 1, blob_id: nil, **video_overrides)
        blob_id ||= video_id + 900
        {
          video: video_row(id: video_id, user_id: user_id, **video_overrides),
          attachment: attachment_row(id: video_id + 500, record_id: video_id, blob_id: blob_id),
          blob: blob_row(id: blob_id)
        }
      end

      def preflight(bundles)
        source = Snapshot::VideoSource.new(
          videos: bundles.map { |b| b[:video] },
          attachments: bundles.filter_map { |b| b[:attachment] },
          blobs: bundles.filter_map { |b| b[:blob] }.uniq { |r| r["id"] }
        )
        VideoPreflight.call(brand: @brand, source: source)
      end

      # --- happy path ------------------------------------------------------

      test "preflights a video whose owner profile was imported" do
        import_owner(1)

        result = nil
        assert_difference(
          -> { Migration::MediaObjectRef.count } => 1,
          -> { Migration::MediaAttachmentRef.count } => 1
        ) do
          result = preflight([ bundle(video_id: 1, user_id: 1) ])
        end

        h = result.reconciliation.to_h
        assert h["balanced"]
        assert_equal 1, h.dig("dispositions", "preflighted")
        assert_equal 1, h.dig("created", "media_object_refs_created")

        object = Migration::MediaObjectRef.sole
        assert_equal "date9ja", object.source_system
        assert_equal "901", object.source_blob_id
        assert object.preflight_preflighted?

        attachment = Migration::MediaAttachmentRef.sole
        assert_equal "profile_video", attachment.source_record_entity
        assert_equal "1", attachment.source_record_id
        assert_equal "video", attachment.attachment_name
        assert attachment.preflight_preflighted?
      end

      test "processes all videos deterministically and creates no D8N media" do
        import_owner(1)
        import_owner(2)
        import_owner(3)
        bundles = [ bundle(video_id: 3, user_id: 3), bundle(video_id: 1, user_id: 1), bundle(video_id: 2, user_id: 2) ]

        assert_no_difference([
          -> { ProfileVideo.count }, -> { ActiveStorage::Attachment.count }, -> { ActiveStorage::Blob.count }
        ]) do
          assert_no_enqueued_jobs { preflight(bundles) }
        end

        assert_equal %w[1 2 3],
          Migration::MediaAttachmentRef.order(:source_record_id).pluck(:source_record_id)
      end

      test "explicit column allowlist excludes locator, filename and rejection_reason" do
        forbidden = %w[key filename service_name metadata rejection_reason]
        assert_empty(Snapshot::VideoSource::VIDEO_COLUMNS & forbidden)
        assert_empty(Snapshot::VideoSource::BLOB_COLUMNS & forbidden)
      end

      # --- moderation ----------------------------------------------------

      test "records every known source moderation bucket and fails closed on unknown" do
        import_owner(1)
        import_owner(2)
        import_owner(3)
        import_owner(4)
        result = preflight([
          bundle(video_id: 1, user_id: 1, moderation_status: 0),
          bundle(video_id: 2, user_id: 2, moderation_status: 1),
          bundle(video_id: 3, user_id: 3, moderation_status: 2),
          bundle(video_id: 4, user_id: 4, moderation_status: 7)
        ])

        m = result.reconciliation.to_h["measures"]
        assert_equal 1, m["moderation_pending"]
        assert_equal 1, m["moderation_approved"]
        assert_equal 1, m["moderation_rejected"]
        assert_equal 1, m["malformed_moderation_values"]
        assert_equal 1, result.reconciliation.to_h.dig("dispositions", "malformed")
        assert_equal 1, result.reconciliation.reason_count("moderation_unmapped")
      end

      test "documented pass-2 mapping covers all three source labels" do
        assert_equal %w[pending approved rejected].sort, VideoModeration::PASS_2_TARGET.keys.sort
        assert_equal :rejected, VideoModeration::PASS_2_TARGET.dig("rejected", :profile_video_status)
      end

      # --- attachment / blob anomalies --------------------------------

      test "a video with no attachment is unavailable" do
        import_owner(1)
        result = preflight([ { video: video_row(id: 1, user_id: 1) } ])

        assert_equal 1, result.reconciliation.to_h.dig("dispositions", "unavailable")
        assert_equal 1, result.reconciliation.reason_count("missing_attachment")
        assert_equal 0, Migration::MediaObjectRef.count
      end

      test "non-ProfileVideo / non-video attachments are ignored by the filter" do
        import_owner(1)
        source = Snapshot::VideoSource.new(
          videos: [ video_row(id: 1, user_id: 1) ],
          attachments: [
            attachment_row(id: 10, record_id: 1, blob_id: 901, name: "poster"),
            attachment_row(id: 11, record_id: 1, blob_id: 901, record_type: "Message")
          ],
          blobs: [ blob_row(id: 901) ]
        )
        result = VideoPreflight.call(brand: @brand, source: source)

        assert_equal 1, result.reconciliation.reason_count("missing_attachment")
      end

      test "a video with two video attachments fails closed" do
        import_owner(1)
        source = Snapshot::VideoSource.new(
          videos: [ video_row(id: 1, user_id: 1) ],
          attachments: [
            attachment_row(id: 10, record_id: 1, blob_id: 901),
            attachment_row(id: 11, record_id: 1, blob_id: 902)
          ],
          blobs: [ blob_row(id: 901), blob_row(id: 902) ]
        )
        result = VideoPreflight.call(brand: @brand, source: source)

        assert_equal 1, result.reconciliation.to_h.dig("dispositions", "failed")
        assert_equal 1, result.reconciliation.reason_count("duplicate_attachment")
        assert_equal 1, result.reconciliation.to_h.dig("measures", "duplicate_attachments")
      end

      test "a missing blob row is unavailable" do
        import_owner(1)
        source = Snapshot::VideoSource.new(
          videos: [ video_row(id: 1, user_id: 1) ],
          attachments: [ attachment_row(id: 10, record_id: 1, blob_id: 999) ],
          blobs: []
        )
        result = VideoPreflight.call(brand: @brand, source: source)

        assert_equal 1, result.reconciliation.to_h.dig("dispositions", "unavailable")
        assert_equal 1, result.reconciliation.reason_count("missing_blob")
      end

      test "an unsupported content type fails but still records evidence" do
        import_owner(1)
        result = preflight([ bundle(video_id: 1, blob_id: 901).tap { |b| b[:blob]["content_type"] = "video/webm" } ])

        assert_equal 1, result.reconciliation.to_h.dig("dispositions", "failed")
        assert_equal 1, result.reconciliation.reason_count("unsupported_content_type")
        object = Migration::MediaObjectRef.sole
        assert object.preflight_failed?
        assert_equal "unsupported_content_type", object.failure_code
      end

      test "quicktime is accepted per the shared ProfileVideo contract" do
        import_owner(1)
        result = preflight([ bundle(video_id: 1, blob_id: 901).tap { |b| b[:blob]["content_type"] = "video/quicktime" } ])

        assert_equal 1, result.reconciliation.to_h.dig("dispositions", "preflighted")
      end

      test "an inconsistent checksum/size fails closed" do
        import_owner(1)
        result = preflight([ bundle(video_id: 1, blob_id: 901).tap { |b| b[:blob]["byte_size"] = 0 } ])

        assert_equal 1, result.reconciliation.reason_count("checksum_size_inconsistent")
        assert_equal 1, result.reconciliation.to_h.dig("measures", "checksum_size_inconsistencies")
      end

      # --- blob reuse ---------------------------------------------------

      test "one reused blob yields one MediaObjectRef and many MediaAttachmentRefs" do
        import_owner(1)
        import_owner(2)
        result = preflight([
          bundle(video_id: 1, user_id: 1, blob_id: 700),
          bundle(video_id: 2, user_id: 2, blob_id: 700)
        ])

        assert_equal 1, Migration::MediaObjectRef.where(source_blob_id: "700").count
        assert_equal 2, Migration::MediaAttachmentRef.count
        assert_equal 1, result.reconciliation.to_h.dig("measures", "blob_reuse_objects")
      end

      # --- owner accounting ------------------------------------------

      test "a video whose owner was not imported is classified, not dropped" do
        result = preflight([ bundle(video_id: 1, user_id: 42) ])

        assert_equal 1, result.reconciliation.to_h.dig("dispositions", "owner_not_imported")
        assert_equal 1, result.reconciliation.reason_count("owner_not_imported")
        assert_equal 1, Migration::MediaObjectRef.count
        assert Migration::MediaAttachmentRef.sole.preflight_owner_not_imported?
      end

      test "rerun upgrades owner_not_imported after the owner profile is imported" do
        bundles = [ bundle(video_id: 1, user_id: 42) ]
        first = preflight(bundles)
        assert_equal 1, first.reconciliation.to_h.dig("dispositions", "owner_not_imported")

        import_owner(42)
        second = preflight(bundles)

        assert_equal 1, second.reconciliation.to_h.dig("dispositions", "preflighted")
        assert_equal 0, second.reconciliation.to_h.dig("dispositions", "already_preflighted")
        assert Migration::MediaAttachmentRef.sole.preflight_preflighted?
      end

      test "a video whose owner has no ReferenceMap mapping is owner_not_imported" do
        result = preflight([ bundle(video_id: 1, user_id: 999) ])

        assert_equal 1, result.reconciliation.to_h.dig("dispositions", "owner_not_imported")
      end

      test "wrong destination type for the owner mapping fails closed" do
        user = User.create!
        membership = BrandMembership.create!(user: user, brand: @brand, status: :active)
        Migration::ReferenceMap.bind!(
          source_system: "date9ja", source_entity: "profile", source_id: "1",
          destination: membership, importer_version: "x", brand: @brand
        )
        result = preflight([ bundle(video_id: 1, user_id: 1) ])

        assert_equal 1, result.reconciliation.to_h.dig("dispositions", "failed")
        assert_equal 1, result.reconciliation.reason_count("owner_binding_conflict")
      end

      test "a suspended owner is classified structurally, not excluded" do
        import_owner(1, status: :suspended)
        result = preflight([ bundle(video_id: 1, user_id: 1) ])

        assert_equal 1, result.reconciliation.to_h.dig("dispositions", "preflighted")
        assert_equal 1, result.reconciliation.to_h.dig("measures", "owners_suspended")
        assert_equal 1, result.reconciliation.reason_count("source_suspended_owner")
      end

      # --- one video per owner --------------------------------------

      test "measures owners with exactly one video" do
        import_owner(1)
        import_owner(2)
        result = preflight([ bundle(video_id: 1, user_id: 1), bundle(video_id: 2, user_id: 2) ])

        m = result.reconciliation.to_h["measures"]
        assert_equal 2, m["owners_total"]
        assert_equal 2, m["owners_with_one_video"]
        assert_equal 0, m["owners_with_multiple_videos"]
      end

      test "multiple kept videos for one owner are quarantined, never arbitrarily chosen" do
        import_owner(1)
        result = preflight([
          bundle(video_id: 1, user_id: 1, blob_id: 701),
          bundle(video_id: 2, user_id: 1, blob_id: 702)
        ])

        assert_equal 2, result.reconciliation.to_h.dig("dispositions", "failed")
        assert_equal 2, result.reconciliation.reason_count("multiple_videos_per_owner")
        assert_equal 1, result.reconciliation.to_h.dig("measures", "owners_with_multiple_videos")
        assert_equal 0, Migration::MediaObjectRef.count
        assert_equal 0, Migration::MediaAttachmentRef.count
      end

      # --- duration (measure only) ---------------------------------

      test "a missing duration is measured and never rejects the row" do
        import_owner(1)
        result = preflight([ bundle(video_id: 1, user_id: 1, duration_seconds: nil) ])

        m = result.reconciliation.to_h["measures"]
        assert_equal 1, m["duration_missing"]
        assert_equal 60, m["max_duration_limit_seconds"]
        assert_equal 1, result.reconciliation.to_h.dig("dispositions", "preflighted")
      end

      test "an invalid duration is measured and never rejects the row" do
        import_owner(1)
        result = preflight([ bundle(video_id: 1, user_id: 1, duration_seconds: 0) ])

        assert_equal 1, result.reconciliation.to_h.dig("measures", "duration_invalid")
        assert_equal 1, result.reconciliation.to_h.dig("dispositions", "preflighted")
      end

      test "a duration within the D8N limit is measured" do
        import_owner(1)
        result = preflight([ bundle(video_id: 1, user_id: 1, duration_seconds: 45) ])

        m = result.reconciliation.to_h["measures"]
        assert_equal 1, m["duration_present"]
        assert_equal 1, m["duration_within_limit"]
        assert_equal 0, m["duration_over_limit"]
        assert_equal 1, result.reconciliation.to_h.dig("dispositions", "preflighted")
      end

      test "a duration over the D8N limit is measured only and still preflights" do
        import_owner(1)
        result = preflight([ bundle(video_id: 1, user_id: 1, duration_seconds: 240) ])

        m = result.reconciliation.to_h["measures"]
        assert_equal 1, m["duration_over_limit"]
        assert_equal 1, result.reconciliation.to_h.dig("dispositions", "preflighted")
        assert Migration::MediaAttachmentRef.sole.preflight_preflighted?
      end

      # --- idempotency & drift -------------------------------------

      test "a second identical run is a full no-op" do
        import_owner(1)
        import_owner(2)
        bundles = [ bundle(video_id: 1, user_id: 1), bundle(video_id: 2, user_id: 2) ]
        preflight(bundles)

        result = nil
        assert_no_difference([
          -> { Migration::MediaObjectRef.count }, -> { Migration::MediaAttachmentRef.count }
        ]) do
          result = preflight(bundles)
        end

        assert_equal 2, result.reconciliation.to_h.dig("dispositions", "already_preflighted")
        assert_equal 0, result.reconciliation.to_h.dig("dispositions", "preflighted")
        assert_equal 0, result.reconciliation.to_h.dig("created", "media_object_refs_created")
      end

      test "blob metadata drift on rerun fails closed" do
        import_owner(1)
        preflight([ bundle(video_id: 1, blob_id: 901) ])

        result = preflight([ bundle(video_id: 1, blob_id: 901).tap { |b| b[:blob]["checksum"] = "changed" } ])

        assert_equal 1, result.reconciliation.to_h.dig("dispositions", "failed")
        assert_equal 1, result.reconciliation.reason_count("blob_metadata_drift")
        assert_equal 1, result.reconciliation.to_h.dig("measures", "binding_conflicts")
      end

      test "attachment drift on rerun fails closed" do
        import_owner(1)
        preflight([ bundle(video_id: 1, blob_id: 901) ])
        source = Snapshot::VideoSource.new(
          videos: [ video_row(id: 1, user_id: 1) ],
          attachments: [ attachment_row(id: 501, record_id: 1, blob_id: 902) ],
          blobs: [ blob_row(id: 902) ]
        )
        result = VideoPreflight.call(brand: @brand, source: source)

        assert_equal 1, result.reconciliation.reason_count("attachment_drift")
        assert_equal 0, result.reconciliation.to_h.dig("created", "media_object_refs_created")
      end

      # --- reconciliation contract ---------------------------------

      test "the reconciliation invariant closes over a mixed batch" do
        import_owner(1)
        result = preflight([
          bundle(video_id: 1, user_id: 1),                       # preflighted
          bundle(video_id: 2, user_id: 42),                      # owner_not_imported
          { video: video_row(id: 3, user_id: 1) },               # unavailable (missing attachment)
          bundle(video_id: 4, user_id: 1, moderation_status: 9)  # malformed
        ])

        h = result.reconciliation.to_h
        assert h["balanced"]
        assert_equal 4, h["videos_considered"]
        assert_equal 4, h["dispositions"].values.sum
      end

      test "reconciliation output contains no checksum, key, name, or per-row id" do
        import_owner(1)
        result = preflight([ bundle(video_id: 1, user_id: 1, blob_id: 12_345) ])

        dump = result.reconciliation.to_h.to_s
        refute_includes dump, "chk-"
        refute_includes dump, "12345"
        refute_includes dump, "P1"
      end

      test "refuses a brand that is not the active date9ja brand" do
        other = Brand.create!(slug: "dateza", name: "DateZA", status: :active)
        assert_raises(VideoPreflight::WrongBrand) do
          VideoPreflight.call(brand: other, source: Snapshot::VideoSource.new(videos: []))
        end
      end
    end
  end
end
