# frozen_string_literal: true

require "test_helper"

module Date9ja
  module Import
    # L1 harness for profile-video Pass 2A (ADR 0029). Synthetic in-memory
    # corpus; no real R2, no snapshot artifact. Real ffmpeg/ffprobe-generated
    # video bytes (the same runtime dependency Media::VideoProcessor requires
    # everywhere) so authoritative duration derivation is genuinely exercised.
    class VideoTransferTest < ActiveSupport::TestCase
      include ActiveJob::TestHelper

      setup do
        @brand = Brand.create!(slug: "date9ja", name: "Date9ja", status: :active,
          auth_methods: %w[email_password])
        @run = SecureRandom.hex(5)
        @mp4 = build_test_h264_mp4_bytes(duration: 2)
        @bytes_by_key = {}
        @locator_rows = {}
      end

      # --- fixtures --------------------------------------------------------

      def owner_sid(user_id) = "#{@run}-u#{user_id}"

      def import_owner(user_id, status: :active)
        user = User.create!
        membership = BrandMembership.create!(user:, brand: @brand, status:)
        profile = Profile.create!(user:, brand: @brand, brand_membership: membership,
          display_name: "P#{user_id}", birthdate: 27.years.ago.to_date, gender: "woman",
          status: (status == :suspended ? :suspended : :draft))
        Migration::ReferenceMap.bind!(source_system: "date9ja", source_entity: "profile",
          source_id: owner_sid(user_id), destination: profile, importer_version: "date9ja-identity-v1", brand: @brand)
        profile
      end

      def rows_for(specs)
        videos = []
        attachments = []
        blobs = []
        specs.each_with_index do |spec, i|
          n = spec[:n] || i
          bytes = spec[:bytes] || @mp4
          vid = "#{@run}-v#{n}"
          bid = "#{@run}-b#{n}"
          aid = "#{@run}-a#{n}"
          key = "legacy#{@run}#{n}"

          videos << { "id" => vid, "user_id" => owner_sid(spec.fetch(:user_id)),
            "duration_seconds" => nil, "moderation_status" => spec[:moderation_status] || 0,
            "created_at" => Time.utc(2024, 1, 1), "reviewed_at" => nil }
          attachments << { "id" => aid, "name" => "video", "record_type" => "ProfileVideo",
            "record_id" => vid, "blob_id" => bid }
          blobs << { "id" => bid, "byte_size" => spec[:byte_size] || bytes.bytesize,
            "checksum" => spec[:checksum] || Digest::MD5.base64digest(bytes),
            "content_type" => spec[:content_type] || "video/mp4" }

          @bytes_by_key[key] = bytes
          @locator_rows[bid] = { key:, service_name: spec[:service_name] || "cloudflare" }
          spec[:vid] = vid
          spec[:bid] = bid
          spec[:aid] = aid
        end
        [ videos, attachments, blobs ]
      end

      def source_from(rows) = Snapshot::VideoSource.new(videos: rows[0], attachments: rows[1], blobs: rows[2])

      def build_corpus(specs)
        rows = rows_for(specs)
        VideoPreflight.call(brand: @brand, source: source_from(rows))
        @specs = specs
        source_from(rows)
      end

      def locator = Snapshot::VideoLocatorSource.new(rows: @locator_rows)

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

      def transfer(source, **opts)
        VideoTransfer.call(brand: @brand, source:, locator:, source_reader:, **opts)
      end

      def final_key_for(spec, content_type: "video/mp4")
        identity = Migration::MediaTransfer::CanonicalKey::Identity.new(
          source_system: "date9ja", source_blob_id: spec[:bid], source_attachment_id: spec[:aid],
          destination_purpose: "profile_video_original", destination_brand: "date9ja",
          canonical_content_type: content_type
        )
        Migration::MediaTransfer::CanonicalKey.final_key(identity)
      end

      # --- happy path ---------------------------------------------------

      test "clean run: verifies, derives duration, adopts a destination original blob" do
        import_owner(1)
        source = build_corpus([ { user_id: 1 } ])

        recon = nil
        assert_no_enqueued_jobs do
          recon = transfer(source).reconciliation
        end

        assert recon.balanced?
        assert recon.phase_a_clean?
        assert_equal 1, recon.count(:destination_adopted)
        assert_equal 1, recon.measure(:destination_uploads_created)
        assert_equal 1, recon.measure(:duration_derived)
        assert_equal 1, recon.measure(:duration_within_limit)
        assert_equal 1, recon.measure(:content_type_mp4)

        blob = ActiveStorage::Blob.find_by(key: final_key_for(@specs[0]))
        assert blob, "destination original blob adopted"
        assert blob.service.exist?(blob.key)
        assert blob.key.start_with?("migrations/media/v3/date9ja/profile_video_original/")
        assert_equal "video/mp4", blob.content_type
      end

      test "Pass 2A creates zero ProfileVideo, zero profile_video ReferenceMap binding, zero jobs" do
        import_owner(1)
        source = build_corpus([ { user_id: 1 } ])

        assert_no_difference([
          -> { ProfileVideo.count },
          -> { ActiveStorage::Attachment.where(record_type: "ProfileVideo").count }
        ]) do
          assert_no_enqueued_jobs { transfer(source) }
        end

        assert_nil Migration::ReferenceMap.resolve(
          source_system: "date9ja", source_entity: "profile_video", source_id: @specs[0][:vid]
        )
      end

      # --- idempotency ------------------------------------------------

      test "a second identical run classifies existing adoption, uploads nothing new" do
        import_owner(1)
        source = build_corpus([ { user_id: 1 } ])
        transfer(source)

        blob_count = ActiveStorage::Blob.count
        recon = transfer(source_from(rows_for(@specs))).reconciliation

        assert_equal 1, recon.count(:already_destination_adopted)
        assert_equal 0, recon.count(:destination_adopted)
        assert_equal 1, recon.measure(:destination_uploads_reused)
        assert_equal blob_count, ActiveStorage::Blob.count
      end

      # --- duration policy -------------------------------------------

      test "over the brand duration limit is quarantined with no destination blob" do
        import_owner(1)
        source = build_corpus([ { user_id: 1 } ])

        recon = stub_method(Media::VideoPolicy, :max_duration_seconds, ->(brand:) { 1 }) do
          transfer(source).reconciliation
        end

        assert_equal 1, recon.count(:quarantined)
        assert_equal 1, recon.reason_count("duration_over_limit")
        assert_equal 1, recon.measure(:duration_over_limit)
        assert_nil ActiveStorage::Blob.find_by(key: final_key_for(@specs[0]))
      end

      test "unreadable duration is quarantined with no destination blob" do
        import_owner(1)
        # structurally valid container, but ffprobe finds no parseable duration
        source = build_corpus([ { user_id: 1, bytes: build_test_mp4_bytes } ])

        recon = transfer(source).reconciliation

        assert_equal 1, recon.count(:quarantined)
        assert_equal 1, recon.reason_count("duration_unreadable")
        assert_nil ActiveStorage::Blob.find_by(key: final_key_for(@specs[0]))
      end

      # --- structural fail-closed matrix ---------------------------

      test "spoofed media (image bytes declared video/mp4) fails closed validation_failed" do
        import_owner(1)
        jpeg = build_test_jpeg_bytes
        source = build_corpus([ { user_id: 1, bytes: jpeg } ])

        recon = transfer(source).reconciliation
        assert_equal 1, recon.count(:validation_failed)
        assert_equal 1, recon.reason_count("not_a_video")
      end

      test "a corrupt/truncated container fails closed malformed_container" do
        import_owner(1)
        source = build_corpus([ { user_id: 1, bytes: @mp4[0, @mp4.bytesize - 60] } ])

        recon = transfer(source).reconciliation
        assert_equal 1, recon.count(:validation_failed)
        assert_equal 1, recon.reason_count("malformed_container")
        assert_equal 1, recon.measure(:container_invalid)
      end

      test "a source byte-size mismatch fails closed source_changed" do
        import_owner(1)
        source = build_corpus([ { user_id: 1, byte_size: @mp4.bytesize + 25 } ])

        recon = transfer(source).reconciliation
        assert_equal 1, recon.count(:source_changed)
        assert_equal 1, recon.reason_count("source_size_mismatch")
      end

      test "a source checksum mismatch fails closed source_changed" do
        import_owner(1)
        source = build_corpus([ { user_id: 1, checksum: Digest::MD5.base64digest("other") } ])

        recon = transfer(source).reconciliation
        assert_equal 1, recon.count(:source_changed)
        assert_equal 1, recon.reason_count("source_checksum_mismatch")
      end

      test "source metadata drift (declared mp4, actual mov) fails closed source_changed" do
        import_owner(1)
        mov = build_test_h264_mov_bytes(duration: 1)
        source = build_corpus([ { user_id: 1, bytes: mov, content_type: "video/mp4" } ])

        recon = transfer(source).reconciliation
        assert_equal 1, recon.count(:source_changed)
        assert_equal 1, recon.reason_count("content_type_drift")
      end

      test "a tampered destination object (row matches, bytes differ) is a binding_conflict" do
        import_owner(1)
        source = build_corpus([ { user_id: 1 } ])
        transfer(source)
        blob = ActiveStorage::Blob.find_by(key: final_key_for(@specs[0]))
        blob.service.upload(blob.key, StringIO.new(build_test_h264_mp4_bytes(duration: 1)))

        recon = transfer(source_from(rows_for(@specs))).reconciliation
        assert_equal 1, recon.count(:binding_conflict)
        assert_equal 1, recon.reason_count("destination_collision")
        assert_equal 1, recon.measure(:destination_collisions)
      end

      test "a remote object with no blob row is a remote_orphan, never adopted" do
        import_owner(1)
        source = build_corpus([ { user_id: 1 } ])
        key = final_key_for(@specs[0])
        ActiveStorage::Blob.service.upload(key, StringIO.new(@mp4))

        recon = transfer(source).reconciliation
        assert_equal 1, recon.count(:binding_conflict)
        assert_equal 1, recon.reason_count("remote_orphan")
        assert_nil ActiveStorage::Blob.find_by(key:)
      end

      test "a video whose owner was not imported is classified, not dropped" do
        source = build_corpus([ { user_id: 99 } ])
        recon = transfer(source).reconciliation

        assert_equal 1, recon.count(:owner_not_imported)
        assert_equal 1, recon.measure(:owner_not_imported)
        assert_nil ActiveStorage::Blob.find_by(key: final_key_for(@specs[0]))
      end

      test "a source video on an unexpected storage service is a global blocker" do
        import_owner(1)
        source = build_corpus([ { user_id: 1, service_name: "amazon" } ])

        assert_raises(Migration::MediaTransfer::GlobalBlocker) { transfer(source) }
      end

      test "refuses a brand that is not the active date9ja brand" do
        other = Brand.create!(slug: "dateza", name: "DateZA", status: :active)
        assert_raises(VideoTransfer::WrongBrand) do
          VideoTransfer.call(brand: other, source: Snapshot::VideoSource.new(videos: []),
            locator:, source_reader:)
        end
      end

      # --- reconciliation contract -------------------------------

      test "the reconciliation invariant closes over a mixed batch" do
        import_owner(1)
        import_owner(2)
        source = build_corpus([
          { n: 0, user_id: 1 },                              # destination_adopted
          { n: 1, user_id: 2, bytes: build_test_jpeg_bytes }, # validation_failed
          { n: 2, user_id: 42 }                              # owner_not_imported
        ])

        h = transfer(source).reconciliation.to_h
        assert h["balanced"]
        assert_equal 3, h["videos_considered"]
        assert_equal 3, h["dispositions"].values.sum
        assert_equal "SOURCE_ACCEPTED / DESTINATION_ADOPTED (pass 2A; NOT transferred)", h["lifecycle"]
        refute h["dispositions"].key?("transferred")
      end

      test "reconciliation output contains no key, checksum, name, or per-row id" do
        import_owner(1)
        source = build_corpus([ { user_id: 1 } ])
        dump = transfer(source).reconciliation.to_h.to_s

        refute_includes dump, @specs[0][:bid]
        refute_includes dump, @specs[0][:vid]
        refute_includes dump, "legacy#{@run}"
        refute_includes dump, Digest::MD5.base64digest(@mp4)
        refute_includes dump, "P1"
      end

      test "multiple videos for one owner are quarantined, never arbitrarily chosen" do
        import_owner(1)
        source = build_corpus([ { n: 0, user_id: 1 }, { n: 1, user_id: 1 } ])

        recon = transfer(source).reconciliation
        assert_equal 2, recon.count(:quarantined)
        assert_equal 2, recon.reason_count("multiple_videos_per_owner")
      end
    end
  end
end
