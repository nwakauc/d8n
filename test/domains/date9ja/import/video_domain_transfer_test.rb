# frozen_string_literal: true

require "test_helper"

module Date9ja
  module Import
    # L1 harness for profile-video Pass 2B (ADR 0029) — stage: :domain.
    # Real ffmpeg/ffprobe-generated video bytes so processing, playback and
    # poster derivation are genuinely exercised. No real R2, no snapshot artifact.
    class VideoDomainTransferTest < ActiveSupport::TestCase
      include ActiveJob::TestHelper

      setup do
        @brand = Brand.create!(slug: "date9ja", name: "Date9ja", status: :active,
          auth_methods: %w[email_password])
        @run = SecureRandom.hex(5)
        @mp4 = build_test_h264_mp4_bytes(duration: 2)
        @bytes_by_key = {}
        @locator_rows = {}
      end

      # --- fixtures -----------------------------------------------------

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

      def domain_transfer(source, **opts)
        perform_enqueued_jobs do
          VideoTransfer.call(brand: @brand, source:, locator:, source_reader:, stage: :domain, **opts)
        end
      end

      def final_key_for(spec, content_type: "video/mp4")
        identity = Migration::MediaTransfer::CanonicalKey::Identity.new(
          source_system: "date9ja", source_blob_id: spec[:bid], source_attachment_id: spec[:aid],
          destination_purpose: "profile_video_original", destination_brand: "date9ja",
          canonical_content_type: content_type
        )
        Migration::MediaTransfer::CanonicalKey.final_key(identity)
      end

      def bound_video(spec)
        Migration::ReferenceMap.resolved(source_system: "date9ja", source_entity: "profile_video", source_id: spec[:vid])
      end

      # --- clean domain migration ------------------------------------

      test "clean run: ProfileVideo + attachment + binding + processing + playback + poster + ready + purge" do
        profile = import_owner(1)
        source = build_corpus([ { user_id: 1, moderation_status: 1 } ])

        recon = domain_transfer(source).reconciliation

        assert recon.balanced?
        assert recon.clean?
        assert_equal 1, recon.count(:ready)
        assert_equal 1, recon.measure(:profile_videos_created)
        assert_equal 1, recon.measure(:reference_map_bindings_created)
        assert_equal 1, recon.measure(:processing_succeeded)
        assert_equal 1, recon.measure(:playback_validated)
        assert_equal 1, recon.measure(:poster_validated)
        assert_equal "domain", recon.to_h["stage"]

        video = bound_video(@specs[0])
        assert video, "ReferenceMap binding created"
        assert_equal profile.id, video.profile_id
        assert_equal profile.user_id, video.user_id
        assert_equal @brand.id, video.brand_id
        assert video.approved?
        assert video.processing_ready?
        assert video.playback.attached?
        assert video.poster.attached?
        assert_equal final_key_for(@specs[0]), video.metadata["raw_object_key"]
        assert video.playback.blob.key.start_with?("migrations/media/v3/date9ja/profile_video_original/")
        assert_not video.video.attached?, "raw original purged after ready"
        assert video.deliverable?
      end

      test "moderation preservation: rejected -> hidden, pending -> visible" do
        import_owner(1)
        import_owner(2)
        source = build_corpus([
          { n: 0, user_id: 1, moderation_status: 2 },
          { n: 1, user_id: 2, moderation_status: 0 }
        ])
        domain_transfer(source)

        rejected = bound_video(@specs[0])
        assert rejected.rejected?
        assert rejected.hidden?

        pending = bound_video(@specs[1])
        assert pending.pending_review?
        assert pending.visible?
      end

      # --- idempotency --------------------------------------------------

      test "second complete run: already_ready, no duplicate ProfileVideo / attachment / binding / processing" do
        import_owner(1)
        source = build_corpus([ { user_id: 1 } ])
        domain_transfer(source)

        video = bound_video(@specs[0])
        playback_key = video.playback.blob.key
        counts = { pv: ProfileVideo.count, blob: ActiveStorage::Blob.count,
                   ref: LegacyReference.count }

        recon = domain_transfer(source_from(rows_for(@specs))).reconciliation

        assert_equal 1, recon.count(:already_ready)
        assert_equal 0, recon.count(:ready)
        assert_equal 0, recon.measure(:processing_succeeded)
        assert_equal counts[:pv], ProfileVideo.count
        assert_equal counts[:blob], ActiveStorage::Blob.count
        assert_equal counts[:ref], LegacyReference.count
        assert_equal playback_key, bound_video(@specs[0]).reload.playback.blob.key
      end

      test "restart after successful purge does not recreate the raw original" do
        import_owner(1)
        source = build_corpus([ { user_id: 1 } ])
        domain_transfer(source)
        video = bound_video(@specs[0])
        assert_not video.video.attached?
        raw_key = video.metadata["raw_object_key"]

        domain_transfer(source_from(rows_for(@specs)))

        video.reload
        assert_not video.video.attached?, "raw must stay purged"
        assert_nil ActiveStorage::Blob.find_by(key: raw_key)
      end

      # --- resume windows (interruption recovery) -------------------

      test "resume window D/E: bound + processing incomplete -> resumes to ready without rebuild" do
        import_owner(1)
        source = build_corpus([ { user_id: 1 } ])
        # First pass: adopt + Phase-B bind succeeds, then the processing job
        # "crashes" (raises a transient error) leaving the ProfileVideo bound but
        # not ready.
        stub_method(Media::VideoProcessor, :call, ->(_b) { raise Media::VideoProcessor::TimedOut, "crash" }) do
          VideoTransfer.call(brand: @brand, source:, locator:, source_reader:, stage: :domain) rescue nil
        end
        video = bound_video(@specs[0])
        assert video, "binding survived the processing crash"
        assert_not video.processing_ready?
        pv_count = ProfileVideo.count

        recon = domain_transfer(source_from(rows_for(@specs))).reconciliation

        assert_equal 1, recon.count(:ready)
        assert_equal pv_count, ProfileVideo.count, "resumed, not rebuilt"
        assert bound_video(@specs[0]).processing_ready?
      end

      # --- fail-closed matrix -------------------------------------

      test "owner not imported -> owner_not_imported, no ProfileVideo" do
        source = build_corpus([ { user_id: 77 } ])
        recon = domain_transfer(source).reconciliation
        assert_equal 1, recon.count(:owner_not_imported)
        assert_equal 0, ProfileVideo.count
      end

      test "over the brand duration limit -> quarantined, no ProfileVideo, no binding" do
        import_owner(1)
        source = build_corpus([ { user_id: 1 } ])
        recon = stub_method(Media::VideoPolicy, :max_duration_seconds, ->(brand:) { 1 }) do
          domain_transfer(source).reconciliation
        end
        assert_equal 1, recon.count(:quarantined)
        assert_equal 0, ProfileVideo.count
        assert_nil bound_video(@specs[0])
      end

      test "Pass-2A blob checksum mismatch -> source_changed, no ProfileVideo" do
        import_owner(1)
        source = build_corpus([ { user_id: 1, checksum: Digest::MD5.base64digest("other") } ])
        recon = domain_transfer(source).reconciliation
        assert_equal 1, recon.count(:source_changed)
        assert_equal 0, ProfileVideo.count
      end

      test "spoofed image bytes -> validation_failed, no ProfileVideo" do
        import_owner(1)
        source = build_corpus([ { user_id: 1, bytes: build_test_jpeg_bytes } ])
        recon = domain_transfer(source).reconciliation
        assert_equal 1, recon.count(:validation_failed)
        assert_equal 0, ProfileVideo.count
      end

      test "a conflicting ReferenceMap (source video already bound to a different ProfileVideo) fails closed" do
        p1 = import_owner(1)
        source = build_corpus([ { user_id: 1 } ])
        # Pre-bind this source video to an unrelated ProfileVideo for a different profile.
        other = import_owner(2)
        rogue = ProfileVideo.new(profile: other, user: other.user, brand: @brand,
          status: :approved, visibility: :visible)
        rogue.video.attach(io: StringIO.new(@mp4), filename: "r.mp4", content_type: "video/mp4")
        rogue.save!
        Migration::ReferenceMap.bind!(source_system: "date9ja", source_entity: "profile_video",
          source_id: @specs[0][:vid], destination: rogue, importer_version: "x", brand: @brand)

        recon = domain_transfer(source_from(rows_for(@specs))).reconciliation
        assert_equal 1, recon.count(:binding_conflict)
        assert_equal rogue.id, bound_video(@specs[0]).id, "binding never rewritten"
      end

      test "one-video-per-profile invariant: a pre-existing live ProfileVideo blocks the migration" do
        profile = import_owner(1)
        source = build_corpus([ { user_id: 1 } ])
        squatter = ProfileVideo.new(profile:, user: profile.user, brand: @brand,
          status: :approved, visibility: :visible)
        squatter.video.attach(io: StringIO.new(@mp4), filename: "s.mp4", content_type: "video/mp4")
        squatter.save!

        recon = domain_transfer(source).reconciliation
        assert_equal 1, recon.count(:binding_conflict)
        assert_equal 1, recon.reason_count("one_video_invariant")
        assert_nil bound_video(@specs[0])
      end

      test "processing failure (unusable container after adoption) -> processing_failed" do
        import_owner(1)
        source = build_corpus([ { user_id: 1 } ])
        recon = stub_method(Media::VideoProcessor, :call, ->(_b) { raise Media::VideoProcessor::TranscodeFailed, "bad" }) do
          domain_transfer(source).reconciliation
        end
        assert_equal 1, recon.count(:processing_failed)
        video = bound_video(@specs[0])
        assert video.processing_failed?, "ProfileVideo + binding exist but not ready"
      end

      test "an invalid playback rendition never reaches ready (review Finding 1)" do
        import_owner(1)
        source = build_corpus([ { user_id: 1 } ])
        # Job reports success but its playback rendition is not a valid container.
        bogus = Media::VideoProcessor::Result.new(
          rendition_bytes: "not a real mp4 container".b, transcoded: true,
          poster_bytes: build_test_jpeg_bytes, width: 64, height: 64, duration_seconds: 2.0
        )
        recon = stub_method(Media::VideoProcessor, :call, ->(_b) { bogus }) do
          domain_transfer(source).reconciliation
        end
        assert_equal 0, recon.count(:ready)
        assert_equal 1, recon.count(:processing_failed) + recon.count(:derivative_validation_failed)
        video = bound_video(@specs[0])
        assert_not video.processing_ready?
        assert_not video.playback.attached?
        assert video.video.attached?, "raw not purged"
      end

      # --- transaction safety ------------------------------------

      test "RemoteIOUnderLock stays fatal: no remote validation runs inside Phase B" do
        import_owner(1)
        source = build_corpus([ { user_id: 1 } ])
        # If any remote I/O (R2 read / ffprobe / derivative validation) ran under
        # the Phase-B LockGuard, the run would raise RemoteIOUnderLock.
        assert_nothing_raised { domain_transfer(source) }
        assert_equal 1, domain_transfer(source_from(rows_for(@specs))).reconciliation.count(:already_ready)
      end

      # --- reconciliation / PII ---------------------------------

      test "reconciliation invariant closes over a mixed batch and never emits `transferred`" do
        import_owner(1)
        import_owner(2)
        source = build_corpus([
          { n: 0, user_id: 1 },                              # ready
          { n: 1, user_id: 2, bytes: build_test_jpeg_bytes }, # validation_failed
          { n: 2, user_id: 99 }                              # owner_not_imported
        ])
        h = domain_transfer(source).reconciliation.to_h
        assert h["balanced"]
        assert_equal 3, h["videos_considered"]
        assert_equal 3, h["dispositions"].values.sum
        refute h["dispositions"].key?("transferred")
      end

      test "reconciliation output contains no key, checksum, name, or per-row id" do
        import_owner(1)
        source = build_corpus([ { user_id: 1 } ])
        dump = domain_transfer(source).reconciliation.to_h.to_s
        refute_includes dump, @specs[0][:bid]
        refute_includes dump, @specs[0][:vid]
        refute_includes dump, "legacy#{@run}"
        refute_includes dump, Digest::MD5.base64digest(@mp4)
        refute_includes dump, "P1"
      end
    end
  end
end
