# frozen_string_literal: true

require "test_helper"

module Media
  # Review Finding 1 regression: an existing deterministic-key derivative blob
  # may be REUSED only after its ACTUAL remote bytes are independently validated.
  # Every test here FAILS on the reviewed implementation (which reused
  # `ActiveStorage::Blob.find_by(key:)` on key identity alone).
  class ProcessProfileVideoJobDerivativeIntegrityTest < ActiveJob::TestCase
    setup do
      @brand = Brand.create!(slug: "date9ja", name: "Date9ja")
      @user = User.create!
      @membership = BrandMembership.create!(brand: @brand, user: @user)
      @profile = Profile.create!(brand: @brand, user: @user, brand_membership: @membership,
        display_name: "Ada", birthdate: 26.years.ago.to_date, gender: "woman")
      @service = ActiveStorage::Blob.service.name.to_s
      @raw_bytes = build_test_h264_mp4_bytes(duration: 1)
      @raw_key = "migrations/media/v3/date9ja/profile_video_original/#{SecureRandom.uuid}/original.mp4"
      @playback_key = Media::ObjectKey.profile_video_playback(@raw_key)
      @poster_key = Media::ObjectKey.profile_video_poster(@raw_key)
      @video = build_video
      @good_playback = build_test_h264_mp4_bytes(duration: 1)
      @good_poster = build_test_jpeg_bytes.b
    end

    def build_video
      raw = ActiveStorage::Blob.create_and_upload!(io: StringIO.new(@raw_bytes), key: @raw_key,
        filename: "original.mp4", content_type: "video/mp4", service_name: @service)
      v = ProfileVideo.new(profile: @profile, user: @user, brand: @brand,
        status: :approved, visibility: :visible)
      v.video.attach(raw)
      v.save!
      v
    end

    def result(playback: @good_playback, poster: @good_poster)
      Media::VideoProcessor::Result.new(rendition_bytes: playback, transcoded: true,
        poster_bytes: poster, width: 64, height: 64, duration_seconds: 1.0)
    end

    def claimed_job
      job = ProcessProfileVideoJob.new
      token = SecureRandom.uuid
      job.instance_variable_set(:@token, token)
      @video.update_columns(processing_state: ProfileVideo.processing_states[:processing],
        processing_started_at: Time.current, processing_claim_token: token)
      job
    end

    def seed_blob(key, bytes, content_type)
      ActiveStorage::Blob.create_and_upload!(io: StringIO.new(bytes), key:,
        filename: File.basename(key), content_type:, service_name: @service)
    end

    def run_finalize!
      job = claimed_job
      err = assert_raises(ProcessProfileVideoJob::TransientError) { job.send(:finalize!, @video.id, result) }
      @video.reload
      assert_not @video.processing_ready?, "must NOT mark ready"
      assert @video.video.attached?, "must NOT purge the raw original"
      assert_not @video.playback.attached?
      assert_not @video.poster.attached?
      err
    end

    # --- playback existing-blob failure modes -----------------------

    test "existing playback blob with tampered remote bytes -> fail closed, no ready, no purge" do
      blob = seed_blob(@playback_key, @good_playback, "video/mp4")
      blob.service.upload(@playback_key, StringIO.new("tampered not a container".b)) # remote != metadata
      run_finalize!
    end

    test "existing playback blob whose checksum/size disagree with the remote bytes -> fail closed" do
      seed_blob(@playback_key, @good_playback, "video/mp4")
      ActiveStorage::Blob.find_by(key: @playback_key).update_columns(checksum: Digest::MD5.base64digest("other"))
      run_finalize!
    end

    test "existing playback blob at the key but not a valid container -> fail closed" do
      seed_blob(@playback_key, "MZ definitely not an mp4".b + ("\x00" * 64), "video/mp4")
      run_finalize!
    end

    test "existing playback blob on the WRONG service -> fail closed" do
      # brand_test is a real configured disk service distinct from the default.
      ActiveStorage::Blob.create_and_upload!(io: StringIO.new(@good_playback), key: @playback_key,
        filename: "playback.mp4", content_type: "video/mp4", service_name: "brand_test")
      run_finalize!
    end

    # --- poster existing-blob failure modes -------------------------

    test "existing poster blob with a non-decodable body -> fail closed, no ready, no purge" do
      seed_blob(@poster_key, "not a jpeg at all".b, "image/jpeg")
      run_finalize!
    end

    test "existing poster blob whose bytes are not JPEG-magic -> fail closed" do
      png = Vips::Image.black(8, 8).write_to_buffer(".png").b
      seed_blob(@poster_key, png, "image/jpeg")
      run_finalize!
    end

    # --- ABA / candidate substitution ------------------------------

    test "a candidate validated then swapped before attach -> stale validation does not authorize the changed object" do
      # Freshly-created valid candidates pass validation; then a concurrent
      # writer replaces the blob row at the playback key just before the txn.
      job = claimed_job
      original = Media::PlaybackDerivative.method(:playback_blob_valid?)
      swapped = false
      replacement = lambda do |**kw|
        ok = original.call(**kw)
        unless swapped
          swapped = true
          ActiveStorage::Blob.find_by(key: kw[:expected_key])&.destroy
          ActiveStorage::Blob.create_and_upload!(io: StringIO.new("swapped".b), key: kw[:expected_key],
            filename: "playback.mp4", content_type: "video/mp4", service_name: kw[:expected_service])
        end
        ok
      end
      stub_method(Media::PlaybackDerivative, :playback_blob_valid?, replacement) do
        job.send(:finalize!, @video.id, result) # fails closed (derivative_conflict), does not raise
      end
      @video.reload
      assert @video.processing_failed?, "the swapped candidate is rejected — terminal failure"
      assert @video.processing_terminal_failure?
      assert_not @video.processing_ready?
      assert @video.video.attached?, "raw not purged"
      assert_not @video.playback.attached?
    end

    # --- valid reuse ----------------------------------------------

    test "an existing CORRECT playback+poster derivative is safely reused, no duplicate blobs" do
      pb = seed_blob(@playback_key, @good_playback, "video/mp4")
      po = seed_blob(@poster_key, @good_poster, "image/jpeg")

      job = claimed_job
      perform_enqueued_jobs { job.send(:finalize!, @video.id, result) }

      @video.reload
      assert @video.processing_ready?
      assert_equal pb.id, @video.playback.blob.id, "reused, not recreated"
      assert_equal po.id, @video.poster.blob.id
      assert_equal 1, ActiveStorage::Blob.where(key: @playback_key).count, "no duplicate playback blob"
      assert_equal 1, ActiveStorage::Blob.where(key: @poster_key).count, "no duplicate poster blob"
      assert_not @video.video.attached?, "raw purged after validated ready"
    end

    test "no pre-existing blob -> fresh derivatives created, validated, ready" do
      job = claimed_job
      perform_enqueued_jobs { job.send(:finalize!, @video.id, result) }

      @video.reload
      assert @video.processing_ready?
      assert_equal @playback_key, @video.playback.blob.key
      assert_equal @poster_key, @video.poster.blob.key
      assert Media::PlaybackDerivative.valid?(video: @video, expected_playback_key: @playback_key,
        expected_poster_key: @poster_key, expected_service: @service)
    end

    # --- claim ownership -----------------------------------------

    test "a non-owning worker cannot attach/finalize/purge even with valid candidates" do
      seed_blob(@playback_key, @good_playback, "video/mp4")
      seed_blob(@poster_key, @good_poster, "image/jpeg")
      current_token = SecureRandom.uuid
      @video.update_columns(processing_state: ProfileVideo.processing_states[:processing],
        processing_started_at: Time.current, processing_claim_token: current_token)

      stale = ProcessProfileVideoJob.new
      stale.instance_variable_set(:@token, SecureRandom.uuid)
      stale.send(:finalize!, @video.id, result)

      @video.reload
      assert @video.processing_processing?
      assert_equal current_token, @video.processing_claim_token
      assert_not @video.playback.attached?
      assert @video.video.attached?
    end
  end
end
