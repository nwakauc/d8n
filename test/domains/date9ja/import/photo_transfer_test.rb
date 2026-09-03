# frozen_string_literal: true

require "test_helper"
require "vips"

module Date9ja
  module Import
    # L1 harness for profile-photo Pass 2 (MEDIA-TRANSFER.md §21 L1). Synthetic
    # in-memory corpus; no real R2, no snapshot, no media_v2 artifact.
    class PhotoTransferTest < ActiveSupport::TestCase
      include ActiveJob::TestHelper

      setup do
        @brand = Brand.create!(slug: "date9ja", name: "Date9ja", status: :active,
          auth_methods: %w[email_password])
        @run = SecureRandom.hex(5) # unique storage-key namespace per test run
        @jpeg = Vips::Image.black(120, 90).add([ 70 ]).cast("uchar").write_to_buffer(".jpg").b
      end

      # --- fixtures --------------------------------------------------------

      def import_owner(user_id)
        user = User.create!
        membership = BrandMembership.create!(user:, brand: @brand)
        profile = Profile.create!(user:, brand: @brand, brand_membership: membership,
          display_name: "P#{user_id}", birthdate: 27.years.ago.to_date, gender: "woman", status: :draft)
        Migration::ReferenceMap.bind!(source_system: "date9ja", source_entity: "profile",
          source_id: owner_sid(user_id), destination: profile, importer_version: "date9ja-identity-v1", brand: @brand)
        profile
      end

      def owner_sid(user_id) = "#{@run}-u#{user_id}"

      def rows_for(specs)
        photo_rows = []
        attachment_rows = []
        blob_rows = []
        @bytes_by_key ||= {}
        @locator_rows ||= {}

        specs.each_with_index do |spec, i|
          bytes = spec[:bytes] || @jpeg
          bid = "#{@run}-b#{spec[:n] || i}"
          aid = "#{@run}-a#{spec[:n] || i}"
          pid = "#{@run}-p#{spec[:n] || i}"
          key = "legacy/#{bid}"

          photo_rows << { "id" => pid, "user_id" => owner_sid(spec.fetch(:user_id)),
            "position" => spec[:position] || 0, "moderation_status" => spec[:moderation_status] || 1,
            "is_primary" => spec[:is_primary] || false, "created_at" => Time.utc(2024, 1, 1), "reviewed_at" => nil }
          attachment_rows << { "id" => aid, "name" => "image", "record_type" => "Photo",
            "record_id" => pid, "blob_id" => bid }
          blob_rows << { "id" => bid, "byte_size" => bytes.bytesize,
            "checksum" => Digest::MD5.base64digest(bytes), "content_type" => spec[:content_type] || "image/jpeg" }

          @bytes_by_key[key] = bytes
          @locator_rows[bid] = { key:, service_name: spec[:service_name] || "cloudflare" }
          spec[:pid] = pid
        end
        [ photo_rows, attachment_rows, blob_rows ]
      end

      def source_from(rows) = Date9ja::Snapshot::PhotoSource.new(photos: rows[0], attachments: rows[1], blobs: rows[2])

      # Run pass 1 to populate the refs, then return a fresh pass-2 source.
      def build_corpus(specs)
        rows = rows_for(specs)
        Date9ja::Import::PhotoImport.call(brand: @brand, source: source_from(rows))
        @specs = specs
        source_from(rows)
      end

      def locator = Date9ja::Snapshot::MediaLocatorSource.new(rows: @locator_rows)

      def source_reader
        bytes_by_key = @bytes_by_key
        Class.new do
          define_method(:head) { |key| bytes_by_key.key?(key) ? { byte_size: bytes_by_key[key].bytesize } : nil }
          define_method(:download) do |key, io:, byte_ceiling:, chunk_size: 5.megabytes|
            b = bytes_by_key.fetch(key)
            raise Date9ja::Storage::SourceReader::ByteCeilingExceeded if b.bytesize > byte_ceiling

            io.write(b)
            io.flush
            b.bytesize
          end
        end.new
      end

      def run_transfer(source, **opts)
        perform_enqueued_jobs do
          Date9ja::Import::PhotoTransfer.call(brand: @brand, source:, locator:, source_reader:, **opts)
        end
      end

      def call_transfer(source, **opts)
        Date9ja::Import::PhotoTransfer.call(brand: @brand, source:, locator:, source_reader:, **opts)
      end

      def photo_source_id(index = 0) = @specs[index][:pid]

      # --- tests ---------------------------------------------------------

      test "clean run: transfers, binds ReferenceMap, and processes to ready" do
        profile = import_owner(1)
        source = build_corpus([ { user_id: 1, moderation_status: 1 } ])

        recon = run_transfer(source).reconciliation

        assert recon.balanced?
        assert_equal 1, recon.count(:transferred)
        assert_equal 1, recon.measure(:profile_photos_created)
        assert_equal 1, recon.measure(:reference_map_bindings_created)
        assert recon.cutover_ready?

        photo = Migration::ReferenceMap.resolved(source_system: "date9ja", source_entity: "photo", source_id: photo_source_id)
        assert_equal profile.id, photo.profile_id
        assert photo.approved?
        assert photo.processing_ready?
        assert photo.display_image.blob.key.start_with?("migrations/media/v3/date9ja/profile_photo_original/")
      end

      test "moderation mapping: pending->visible, rejected->hidden" do
        import_owner(1)
        source = build_corpus([
          { n: 0, user_id: 1, moderation_status: 0, position: 0 },
          { n: 1, user_id: 1, moderation_status: 2, position: 1 }
        ])
        run_transfer(source)

        pending = Migration::ReferenceMap.resolved(source_system: "date9ja", source_entity: "photo", source_id: photo_source_id(0))
        rejected = Migration::ReferenceMap.resolved(source_system: "date9ja", source_entity: "photo", source_id: photo_source_id(1))
        assert pending.pending_review?
        assert pending.visible?
        assert rejected.rejected?
        assert rejected.hidden?
      end

      test "idempotent: a second run creates zero new photos or objects" do
        import_owner(1)
        source = build_corpus([ { user_id: 1 } ])
        run_transfer(source)

        photos_before = ProfilePhoto.count
        blobs_before = ActiveStorage::Blob.count

        result = run_transfer(source_from(rows_for(@specs)))

        assert_equal 1, result.reconciliation.count(:already_transferred)
        assert_equal photos_before, ProfilePhoto.count
        assert_equal blobs_before, ActiveStorage::Blob.count
      end

      test "owner not imported: no ProfilePhoto, evidence retained" do
        source = build_corpus([ { user_id: 99 } ])
        result = run_transfer(source)

        assert_equal 1, result.reconciliation.count(:owner_not_imported)
        assert_equal 0, ProfilePhoto.count
        refute result.reconciliation.cutover_ready?
      end

      test "multiple primary for one owner: quarantined, never guessed" do
        import_owner(1)
        source = build_corpus([
          { n: 0, user_id: 1, is_primary: true },
          { n: 1, user_id: 1, is_primary: true }
        ])
        result = run_transfer(source)

        assert_equal 2, result.reconciliation.count(:quarantined)
        assert_equal 1, result.reconciliation.measure(:owners_multiple_primary_quarantined)
        assert_equal 0, ProfilePhoto.count
      end

      test "source checksum drift since preflight: source_changed, fail closed" do
        import_owner(1)
        source = build_corpus([ { user_id: 1 } ])
        @bytes_by_key["legacy/#{@run}-b0"] = @jpeg + "tampered".b

        result = run_transfer(source)
        assert_equal 1, result.reconciliation.count(:source_changed)
        assert_equal 0, ProfilePhoto.count
      end

      test "mapping drift: existing binding now resolves to a different owner -> binding_conflict, no re-key" do
        import_owner(1)
        source = build_corpus([ { user_id: 1 } ])
        run_transfer(source)

        u2 = User.create!
        m2 = BrandMembership.create!(user: u2, brand: @brand)
        other = Profile.create!(user: u2, brand: @brand, brand_membership: m2,
          display_name: "P2", birthdate: 27.years.ago.to_date, gender: "woman", status: :draft)
        Migration::ReferenceMap.resolve(source_system: "date9ja", source_entity: "profile", source_id: owner_sid(1))
          .update_columns(destination_id: other.id)

        result = run_transfer(source_from(rows_for(@specs)))

        assert_equal 1, result.reconciliation.count(:binding_conflict)
        assert_equal 1, result.reconciliation.measure(:mapping_drift)
        refute result.reconciliation.cutover_ready?
      end

      test "global blocker: a non-cloudflare source service aborts the whole run" do
        import_owner(1)
        source = build_corpus([ { user_id: 1, service_name: "amazon" } ])
        assert_raises(Migration::MediaTransfer::GlobalBlocker) { call_transfer(source) }
      end

      test "reconciliation output is PII-free and balanced" do
        import_owner(1)
        source = build_corpus([ { user_id: 1 } ])
        h = run_transfer(source).reconciliation.to_h

        assert h["balanced"]
        json = h.to_json
        refute_match(%r{legacy/|migrations/media|@}, json)
      end

      # --- Finding 1: authoritative chain, no prefix inference ----------------

      def bound_photo(source_id: nil)
        Migration::ReferenceMap.resolved(source_system: "date9ja", source_entity: "photo",
          source_id: source_id || photo_source_id)
      end

      test "wrong original key with the migration prefix is NOT already_transferred" do
        import_owner(1)
        run_transfer(build_corpus([ { user_id: 1 } ]))
        photo = bound_photo
        # Swap the (still-present, pre-purge) raw to a wrong-but-prefixed key.
        wrong = "migrations/media/v3/date9ja/profile_photo_original/#{SecureRandom.uuid}/original.jpg"
        photo.image.blob.update_columns(key: wrong) if photo.image.attached?
        photo.update_columns(processing_state: ProfilePhoto.processing_states[:pending])

        result = run_transfer(source_from(rows_for(@specs)))
        assert_equal 1, result.reconciliation.count(:binding_conflict)
        assert_equal 0, result.reconciliation.count(:already_transferred)
      end

      test "raw attached but processing pending/failed/stale is resume, not already_transferred" do
        import_owner(1)
        source = build_corpus([ { user_id: 1 } ])
        # enqueue mode + zero drain -> job never runs -> pending, raw attached, bound.
        r1 = run_transfer_no_perform(source, processing: :enqueue, drain_timeout: 0)
        clear_enqueued_jobs
        assert_equal 1, r1.reconciliation.count(:processing_failed) # drain timeout, not transferred
        assert_equal 0, r1.reconciliation.count(:transferred)
        assert bound_photo.image.attached?
        assert bound_photo.processing_pending?

        # rerun -> resume processing (no NEW Phase A original blob; the raw is
        # replaced 1:1 by the display derivative).
        raw_blob_id = bound_photo.image.blob.id
        r2 = run_transfer(source_from(rows_for(@specs)))
        assert_equal 1, r2.reconciliation.count(:transferred)
        assert_equal 0, r2.reconciliation.count(:already_transferred)
        assert bound_photo.reload.processing_ready?
        assert bound_photo.display_image.attached?
        assert_nil ActiveStorage::Blob.find_by(id: raw_blob_id), "raw purged after processing, not re-created"
      end

      test "plan drift on a bound photo (position changed) is binding_conflict" do
        import_owner(1)
        run_transfer(build_corpus([ { user_id: 1 } ]))
        bound_photo.update_columns(position: 5)

        result = run_transfer(source_from(rows_for(@specs)))
        assert_equal 1, result.reconciliation.count(:binding_conflict)
      end

      test "ready photo whose display was purged (corrupt terminal) is binding_conflict, not already_transferred" do
        import_owner(1)
        run_transfer(build_corpus([ { user_id: 1 } ]))
        photo = bound_photo
        photo.display_image.blob.service.delete(photo.display_image.blob.key)

        result = run_transfer(source_from(rows_for(@specs)))
        assert_equal 1, result.reconciliation.count(:binding_conflict)
        assert_equal 0, result.reconciliation.count(:already_transferred)
      end

      test "owner mapping change between RESOLVE and Phase B fails closed (mapping_drift)" do
        import_owner(1)
        source = build_corpus([ { user_id: 1 } ])

        u2 = User.create!
        m2 = BrandMembership.create!(user: u2, brand: @brand)
        other = Profile.create!(user: u2, brand: @brand, brand_membership: m2,
          display_name: "P2", birthdate: 27.years.ago.to_date, gender: "woman", status: :draft)

        owner_sid1 = owner_sid(1)
        other_id = other.id
        transfer = Date9ja::Import::PhotoTransfer.new(brand: @brand, source:, locator:, source_reader:)
        # Repoint the owner mapping after Phase A finishes, before Phase B.
        transfer.define_singleton_method(:run_media_transfer) do |**kw|
          super(**kw).tap do
            Migration::ReferenceMap.resolve(source_system: "date9ja", source_entity: "profile",
              source_id: owner_sid1).update_columns(destination_id: other_id)
          end
        end

        result = perform_enqueued_jobs { transfer.call }
        assert_equal 1, result.reconciliation.count(:binding_conflict)
        assert_equal 1, result.reconciliation.measure(:mapping_drift)
        assert_equal 0, ProfilePhoto.where(user_id: other.id).count, "must not silently build for the new owner"
      end

      # --- Finding 3: async never reports premature success ------------------

      test "processing fails -> processing_failed, never transferred" do
        import_owner(1)
        source = build_corpus([ { user_id: 1 } ])
        r = nil
        stub_method(Media::ProcessProfilePhotoJob, :perform_now,
          ->(id) { ProfilePhoto.where(id:).update_all(processing_state: ProfilePhoto.processing_states[:failed], metadata: { "processing_failure_kind" => "terminal" }) }) do
          r = run_transfer(source)
        end
        assert_equal 0, r.reconciliation.count(:transferred)
        assert_equal 1, r.reconciliation.count(:processing_failed)
        assert bound_photo.reload.processing_failed?
      end

      test "enqueue mode: job has not run at reconciliation time -> processing_failed(drain_timeout)" do
        import_owner(1)
        source = build_corpus([ { user_id: 1 } ])
        r = run_transfer_no_perform(source, processing: :enqueue, drain_timeout: 0)
        clear_enqueued_jobs
        assert_equal 0, r.reconciliation.count(:transferred)
        assert_equal 1, r.reconciliation.count(:processing_failed)
        assert_equal 1, r.reconciliation.to_h["reason_codes"].fetch("processing_drain_timeout", 0)
      end

      test "rerun after a successful async transfer is already_transferred" do
        import_owner(1)
        run_transfer(build_corpus([ { user_id: 1 } ]))
        assert bound_photo.processing_ready?

        r2 = run_transfer(source_from(rows_for(@specs)))
        assert_equal 1, r2.reconciliation.count(:already_transferred)
      end

      # --- Review Finding 2: Phase-B existing-binding wrong-profile race --------

      # Runs a real transfer but mutates ReferenceMap state AFTER Phase A and
      # BEFORE Phase B finalization (the exact race Codex described).
      def transfer_racing_phase_b(source, &injector)
        transfer = Date9ja::Import::PhotoTransfer.new(brand: @brand, source:, locator:, source_reader:)
        transfer.define_singleton_method(:run_media_transfer) do |**kw|
          super(**kw).tap { injector.call }
        end
        perform_enqueued_jobs { transfer.call }
      end

      def phase_a_original_key(attachment_n: 0)
        aid = "#{@run}-a#{attachment_n}"
        oref = Migration::MediaAttachmentRef.find_by(source_system: "date9ja", source_attachment_id: aid).media_object_ref
        identity = Migration::MediaTransfer::CanonicalKey::Identity.new(
          source_system: "date9ja", source_blob_id: oref.source_blob_id, source_attachment_id: aid,
          destination_purpose: "profile_photo_original", destination_brand: "date9ja",
          canonical_content_type: "image/jpeg"
        )
        Migration::MediaTransfer::CanonicalKey.final_key(identity)
      end

      def attach_photo(profile:, key:, position: 0, status: :approved, visibility: :visible)
        blob = ActiveStorage::Blob.find_by(key:) || ActiveStorage::Blob.create_and_upload!(
          io: StringIO.new(@jpeg), key:, filename: "original.jpg",
          content_type: "image/jpeg", service_name: Media::StorageResolver.service_name(brand: @brand))
        pp = ProfilePhoto.new(brand: profile.brand, user: profile.user, profile:, position:)
        pp.image.attach(blob)
        pp.save!
        pp.update_columns(status: ProfilePhoto.statuses[status], visibility: ProfilePhoto.visibilities[visibility])
        pp
      end

      def bind_photo(pp, source_id: nil)
        Migration::ReferenceMap.bind!(source_system: "date9ja", source_entity: "photo",
          source_id: source_id || photo_source_id, destination: pp, importer_version: "race", brand: pp.brand)
      end

      test "Phase B: existing binding to the SAME user's other (non-current) profile -> mapping_drift, no reparent" do
        profile_a = import_owner(1)
        stale = Profile.new(user: profile_a.user, brand: @brand, brand_membership: profile_a.brand_membership,
          display_name: "stale", birthdate: 27.years.ago.to_date, gender: "woman", status: :draft)
        stale.deleted_at = Time.current
        stale.save!(validate: false) # a drifted, non-current profile row for the same user
        source = build_corpus([ { user_id: 1 } ])

        result = transfer_racing_phase_b(source) do
          bind_photo(attach_photo(profile: stale, key: "race/#{@run}/x.jpg"))
        end

        assert_equal 1, result.reconciliation.count(:binding_conflict)
        assert_equal 1, result.reconciliation.measure(:mapping_drift)
        assert_equal 0, result.reconciliation.count(:already_transferred)
        assert_equal 0, ProfilePhoto.where(profile: profile_a).count, "must not build for / reparent to the current profile"
      end

      test "Phase B: existing binding owned by a DIFFERENT user -> mapping_drift, fail closed" do
        import_owner(1)
        other = import_owner(2)
        source = build_corpus([ { user_id: 1 } ])

        result = transfer_racing_phase_b(source) do
          bind_photo(attach_photo(profile: other, key: "race/#{@run}/y.jpg"))
        end

        assert_equal 1, result.reconciliation.count(:binding_conflict)
        assert_equal 1, result.reconciliation.measure(:mapping_drift)
      end

      test "Phase B: existing binding in a DIFFERENT brand -> mapping_drift, fail closed" do
        profile_a = import_owner(1)
        other_brand = Brand.create!(slug: "hookus", name: "HookUs", status: :active, auth_methods: %w[email_password])
        ob_membership = BrandMembership.create!(user: profile_a.user, brand: other_brand)
        ob_profile = Profile.create!(user: profile_a.user, brand: other_brand, brand_membership: ob_membership,
          display_name: "elsewhere", birthdate: 27.years.ago.to_date, gender: "woman", status: :draft)
        source = build_corpus([ { user_id: 1 } ])

        result = transfer_racing_phase_b(source) do
          pp = attach_photo(profile: ob_profile, key: "race/#{@run}/z.jpg")
          bind_photo(pp)
        end

        assert_equal 1, result.reconciliation.count(:binding_conflict)
        assert_equal 1, result.reconciliation.measure(:mapping_drift)
      end

      test "Phase B: existing binding to the CORRECT profile with the exact keys -> already_transferred" do
        profile_a = import_owner(1)
        source = build_corpus([ { user_id: 1 } ])

        result = transfer_racing_phase_b(source) do
          pp = attach_photo(profile: profile_a, key: phase_a_original_key)
          bind_photo(pp)
        end

        assert_equal 1, result.reconciliation.count(:already_transferred)
        assert_equal 0, result.reconciliation.count(:binding_conflict)
      end

      private

      def run_transfer_no_perform(source, **opts)
        Date9ja::Import::PhotoTransfer.call(brand: @brand, source:, locator:, source_reader:, **opts)
      end
    end
  end
end
