# frozen_string_literal: true

require "test_helper"

module Date9ja
  module Import
    class PhotoImportTest < ActiveSupport::TestCase
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

      def photo_row(id:, user_id: 1, **overrides)
        {
          "id" => id, "user_id" => user_id, "position" => 0, "moderation_status" => 1,
          "is_primary" => false, "created_at" => Time.utc(2024, 1, 1), "reviewed_at" => nil
        }.merge(overrides.transform_keys(&:to_s))
      end

      def attachment_row(id:, record_id:, blob_id:, name: "image", record_type: "Photo")
        { "id" => id, "name" => name, "record_type" => record_type, "record_id" => record_id, "blob_id" => blob_id }
      end

      def blob_row(id:, byte_size: 200_000, checksum: "chk-#{id}", content_type: "image/jpeg")
        { "id" => id, "byte_size" => byte_size, "checksum" => checksum, "content_type" => content_type }
      end

      # Builds a straightforward photo + its attachment + blob for `user_id`.
      def bundle(photo_id:, user_id: 1, blob_id: nil, **photo_overrides)
        blob_id ||= photo_id + 900
        {
          photo: photo_row(id: photo_id, user_id: user_id, **photo_overrides),
          attachment: attachment_row(id: photo_id + 500, record_id: photo_id, blob_id: blob_id),
          blob: blob_row(id: blob_id)
        }
      end

      def preflight(bundles)
        source = Snapshot::PhotoSource.new(
          photos: bundles.map { |b| b[:photo] },
          attachments: bundles.filter_map { |b| b[:attachment] },
          blobs: bundles.filter_map { |b| b[:blob] }.uniq { |r| r["id"] }
        )
        PhotoImport.call(brand: @brand, source: source)
      end

      # --- happy path ------------------------------------------------------

      test "preflights a photo whose owner profile was imported" do
        import_owner(1)

        result = nil
        assert_difference(
          -> { Migration::MediaObjectRef.count } => 1,
          -> { Migration::MediaAttachmentRef.count } => 1
        ) do
          result = preflight([ bundle(photo_id: 1, user_id: 1) ])
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
        assert_equal "photo", attachment.source_record_entity
        assert_equal "1", attachment.source_record_id
        assert_equal "image", attachment.attachment_name
        assert attachment.preflight_preflighted?
      end

      test "processes all photos deterministically and does not create any D8N media" do
        import_owner(1)
        bundles = [ bundle(photo_id: 3), bundle(photo_id: 1), bundle(photo_id: 2) ]

        assert_no_difference([
          -> { ProfilePhoto.count }, -> { ActiveStorage::Attachment.count }, -> { ActiveStorage::Blob.count }
        ]) do
          assert_no_enqueued_jobs do
            preflight(bundles)
          end
        end

        assert_equal %w[1 2 3],
          Migration::MediaAttachmentRef.order(:source_record_id).pluck(:source_record_id)
      end

      # --- moderation ----------------------------------------------------

      test "records every known source moderation bucket and fails closed on unknown" do
        import_owner(1)
        result = preflight([
          bundle(photo_id: 1, moderation_status: 0),
          bundle(photo_id: 2, moderation_status: 1),
          bundle(photo_id: 3, moderation_status: 2),
          bundle(photo_id: 4, moderation_status: 7)
        ])

        m = result.reconciliation.to_h["measures"]
        assert_equal 1, m["moderation_pending"]
        assert_equal 1, m["moderation_approved"]
        assert_equal 1, m["moderation_rejected"]
        assert_equal 1, m["malformed_moderation_values"]
        assert_equal 1, result.reconciliation.to_h.dig("dispositions", "malformed")
        assert_equal 1, result.reconciliation.reason_count("moderation_unmapped")
      end

      # --- attachment / blob anomalies --------------------------------

      test "a photo with no image attachment is unavailable" do
        import_owner(1)
        result = preflight([ { photo: photo_row(id: 1, user_id: 1) } ])

        assert_equal 1, result.reconciliation.to_h.dig("dispositions", "unavailable")
        assert_equal 1, result.reconciliation.reason_count("missing_attachment")
        assert_equal 0, Migration::MediaObjectRef.count
      end

      test "non-Photo / non-image attachments are ignored by the filter" do
        import_owner(1)
        source = Snapshot::PhotoSource.new(
          photos: [ photo_row(id: 1, user_id: 1) ],
          attachments: [
            attachment_row(id: 10, record_id: 1, blob_id: 901, name: "avatar"),
            attachment_row(id: 11, record_id: 1, blob_id: 901, record_type: "Message")
          ],
          blobs: [ blob_row(id: 901) ]
        )
        result = PhotoImport.call(brand: @brand, source: source)

        assert_equal 1, result.reconciliation.reason_count("missing_attachment")
      end

      test "a photo with two image attachments fails closed" do
        import_owner(1)
        source = Snapshot::PhotoSource.new(
          photos: [ photo_row(id: 1, user_id: 1) ],
          attachments: [
            attachment_row(id: 10, record_id: 1, blob_id: 901),
            attachment_row(id: 11, record_id: 1, blob_id: 902)
          ],
          blobs: [ blob_row(id: 901), blob_row(id: 902) ]
        )
        result = PhotoImport.call(brand: @brand, source: source)

        assert_equal 1, result.reconciliation.to_h.dig("dispositions", "failed")
        assert_equal 1, result.reconciliation.reason_count("duplicate_attachment")
        assert_equal 1, result.reconciliation.to_h.dig("measures", "duplicate_attachments")
      end

      test "a missing blob row is unavailable" do
        import_owner(1)
        source = Snapshot::PhotoSource.new(
          photos: [ photo_row(id: 1, user_id: 1) ],
          attachments: [ attachment_row(id: 10, record_id: 1, blob_id: 999) ],
          blobs: []
        )
        result = PhotoImport.call(brand: @brand, source: source)

        assert_equal 1, result.reconciliation.to_h.dig("dispositions", "unavailable")
        assert_equal 1, result.reconciliation.reason_count("missing_blob")
      end

      test "an unsupported content type fails but still records evidence" do
        import_owner(1)
        result = preflight([ bundle(photo_id: 1, blob_id: 901).tap { |b| b[:blob]["content_type"] = "image/gif" } ])

        assert_equal 1, result.reconciliation.to_h.dig("dispositions", "failed")
        assert_equal 1, result.reconciliation.reason_count("unsupported_content_type")
        object = Migration::MediaObjectRef.sole
        assert object.preflight_failed?
        assert_equal "unsupported_content_type", object.failure_code
      end

      test "an inconsistent checksum/size fails closed" do
        import_owner(1)
        result = preflight([ bundle(photo_id: 1, blob_id: 901).tap { |b| b[:blob]["byte_size"] = 0 } ])

        assert_equal 1, result.reconciliation.reason_count("checksum_size_inconsistent")
        assert_equal 1, result.reconciliation.to_h.dig("measures", "checksum_size_inconsistencies")
      end

      # --- blob reuse ---------------------------------------------------

      test "one reused blob yields one MediaObjectRef and many MediaAttachmentRefs" do
        import_owner(1)
        import_owner(2)
        result = preflight([
          bundle(photo_id: 1, user_id: 1, blob_id: 700),
          bundle(photo_id: 2, user_id: 2, blob_id: 700)
        ])

        assert_equal 1, Migration::MediaObjectRef.where(source_blob_id: "700").count
        assert_equal 2, Migration::MediaAttachmentRef.count
        assert_equal 1, result.reconciliation.to_h.dig("measures", "blob_reuse_objects")
      end

      # --- owner accounting ------------------------------------------

      test "a photo whose owner was not imported is classified, not dropped" do
        result = preflight([ bundle(photo_id: 1, user_id: 42) ])

        assert_equal 1, result.reconciliation.to_h.dig("dispositions", "owner_not_imported")
        assert_equal 1, result.reconciliation.reason_count("owner_not_imported")
        # evidence still recorded for a later pass
        assert_equal 1, Migration::MediaObjectRef.count
        assert Migration::MediaAttachmentRef.sole.preflight_owner_not_imported?
      end

      test "rerun upgrades owner_not_imported after the owner profile is imported" do
        bundles = [ bundle(photo_id: 1, user_id: 42) ]
        first = preflight(bundles)
        assert_equal 1, first.reconciliation.to_h.dig("dispositions", "owner_not_imported")

        import_owner(42)
        second = preflight(bundles)

        assert_equal 1, second.reconciliation.to_h.dig("dispositions", "preflighted")
        assert_equal 0, second.reconciliation.to_h.dig("dispositions", "already_preflighted")
        assert Migration::MediaAttachmentRef.sole.preflight_preflighted?
      end

      test "a suspended owner is classified structurally, not excluded" do
        import_owner(1, status: :suspended)
        result = preflight([ bundle(photo_id: 1, user_id: 1) ])

        assert_equal 1, result.reconciliation.to_h.dig("dispositions", "preflighted")
        assert_equal 1, result.reconciliation.to_h.dig("measures", "owners_suspended")
        assert_equal 1, result.reconciliation.reason_count("source_suspended_owner")
      end

      # --- primary & photo-limit measurement ------------------------

      test "measures primary-photo state per owner without normalizing anomalies" do
        import_owner(1)
        import_owner(2)
        import_owner(3)
        result = preflight([
          bundle(photo_id: 1, user_id: 1, is_primary: true),
          bundle(photo_id: 2, user_id: 1, is_primary: true),   # owner 1: multiple primary
          bundle(photo_id: 3, user_id: 2, is_primary: true),   # owner 2: one primary
          bundle(photo_id: 4, user_id: 3, is_primary: false)   # owner 3: zero primary
        ])

        m = result.reconciliation.to_h["measures"]
        assert_equal 3, m["total_primary_rows"]
        assert_equal 1, m["owners_with_multiple_primary"]
        assert_equal 1, m["owners_with_one_primary"]
        assert_equal 1, m["owners_with_zero_primary"]
        # anomalous owners' photos are still preflighted, never silently changed
        assert_equal 4, result.reconciliation.to_h.dig("dispositions", "preflighted")
      end

      test "measures owners exceeding six photos without dropping any" do
        import_owner(1)
        bundles = (1..7).map { |n| bundle(photo_id: n, user_id: 1) }
        result = preflight(bundles)

        m = result.reconciliation.to_h["measures"]
        assert_equal 1, m["owners_over_six"]
        assert_equal 7, m["max_photos_per_owner"]
        assert_equal 7, result.reconciliation.to_h.dig("dispositions", "preflighted")
        assert_equal 7, Migration::MediaAttachmentRef.count
      end

      # --- idempotency & drift -------------------------------------

      test "a second identical run is a full no-op" do
        import_owner(1)
        import_owner(2)
        bundles = [ bundle(photo_id: 1, user_id: 1), bundle(photo_id: 2, user_id: 2) ]
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
        preflight([ bundle(photo_id: 1, blob_id: 901) ])

        result = preflight([ bundle(photo_id: 1, blob_id: 901).tap { |b| b[:blob]["checksum"] = "changed" } ])

        assert_equal 1, result.reconciliation.to_h.dig("dispositions", "failed")
        assert_equal 1, result.reconciliation.reason_count("blob_metadata_drift")
        assert_equal 1, result.reconciliation.to_h.dig("measures", "binding_conflicts")
      end

      test "attachment drift on rerun fails closed" do
        import_owner(1)
        preflight([ bundle(photo_id: 1, blob_id: 901) ])
        # same attachment id (501) now points at a different blob
        source = Snapshot::PhotoSource.new(
          photos: [ photo_row(id: 1, user_id: 1) ],
          attachments: [ attachment_row(id: 501, record_id: 1, blob_id: 902) ],
          blobs: [ blob_row(id: 902) ]
        )
        result = PhotoImport.call(brand: @brand, source: source)

        assert_equal 1, result.reconciliation.reason_count("attachment_drift")
        assert_equal 0, result.reconciliation.to_h.dig("created", "media_object_refs_created")
      end

      # --- reconciliation contract ---------------------------------

      test "the reconciliation invariant closes over a mixed batch" do
        import_owner(1)
        result = preflight([
          bundle(photo_id: 1, user_id: 1),                                   # preflighted
          bundle(photo_id: 2, user_id: 42),                                  # owner_not_imported
          { photo: photo_row(id: 3, user_id: 1) },                           # unavailable (missing attachment)
          bundle(photo_id: 4, user_id: 1, moderation_status: 9)              # malformed
        ])

        h = result.reconciliation.to_h
        assert h["balanced"]
        assert_equal 4, h["photos_considered"]
        assert_equal 4, h["dispositions"].values.sum
      end

      test "reconciliation output contains no checksum, key, name, or per-row id" do
        import_owner(1)
        result = preflight([ bundle(photo_id: 1, user_id: 1, blob_id: 12_345) ])

        dump = result.reconciliation.to_h.to_s
        refute_includes dump, "chk-"
        refute_includes dump, "12345"
        refute_includes dump, "P1"
      end

      test "refuses a brand that is not the active date9ja brand" do
        other = Brand.create!(slug: "dateza", name: "DateZA", status: :active)
        assert_raises(PhotoImport::WrongBrand) do
          PhotoImport.call(brand: other, source: Snapshot::PhotoSource.new(photos: []))
        end
      end
    end
  end
end
