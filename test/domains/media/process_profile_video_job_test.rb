require "test_helper"

module Media
  class ProcessProfileVideoJobTest < ActiveJob::TestCase
    setup do
      @brand = Brand.create!(slug: "date9ja", name: "Date9ja")
      @user = User.create!
      @membership = BrandMembership.create!(brand: @brand, user: @user)
      @profile = Profile.create!(
        brand: @brand, user: @user, brand_membership: @membership,
        display_name: "Ada", birthdate: 26.years.ago.to_date, gender: "woman"
      )
      # A structurally valid 5s ISO-BMFF original — Media::VideoContainerValidator
      # runs for real in the job now.
      @raw = build_test_mp4_bytes(codec: "avc1", duration_units: 5000, timescale: 1000)
      @video = attach_video(@raw)
    end

    def attach_video(bytes, profile: @profile, user: @user)
      video = ProfileVideo.new(profile:, user:, brand: @brand,
        status: :pending_review, visibility: :visible)
      video.video.attach(io: StringIO.new(bytes), filename: "v.mp4", content_type: "video/mp4")
      video.save!
      video
    end

    def attach_video_for_new_profile(bytes)
      user = User.create!
      membership = BrandMembership.create!(brand: @brand, user:)
      profile = Profile.create!(
        brand: @brand, user:, brand_membership: membership,
        display_name: "P#{user.id}", birthdate: 28.years.ago.to_date, gender: "man"
      )
      attach_video(bytes, profile:, user:)
    end

    def fake_result(poster: "poster-bytes", duration: 4.2)
      Media::VideoProcessor::Result.new(
        rendition_bytes: "playback-bytes", transcoded: true,
        poster_bytes: poster, width: 720, height: 1280, duration_seconds: duration
      )
    end

    test "validates the container, attaches safe derivatives, records duration, marks ready, purges the raw" do
      result = fake_result
      stub_method(Media::VideoProcessor, :call, ->(_bytes) { result }) do
        perform_enqueued_jobs { ProcessProfileVideoJob.perform_now(@video.id) }
      end

      @video.reload
      assert @video.processing_ready?
      assert @video.playback.attached?
      assert @video.poster.attached?
      assert_equal 4, @video.duration_seconds
      assert @video.processed_at.present?
      assert_not @video.video.attached?, "raw original must be purged"
      assert @video.deliverable?
    end

    test "a structurally invalid original is a terminal failure — VideoProcessor never runs" do
      bad = attach_video_for_new_profile("this is not an ISO-BMFF file".b)
      calls = 0
      stub_method(Media::VideoProcessor, :call, ->(_bytes) { calls += 1; fake_result }) do
        ProcessProfileVideoJob.perform_now(bad.id)
      end

      assert_equal 0, calls
      assert bad.reload.processing_failed?
      assert_not bad.deliverable?
    end

    test "a video over the brand duration limit is rejected before any transcode" do
      long = attach_video_for_new_profile(build_test_mp4_bytes(codec: "avc1", duration_units: 90_000, timescale: 1000)) # 90s
      calls = 0
      stub_method(Media::VideoProcessor, :call, ->(_bytes) { calls += 1; fake_result }) do
        ProcessProfileVideoJob.perform_now(long.id)
      end

      assert_equal 0, calls, "container duration gate runs before ffmpeg"
      assert long.reload.processing_failed?
    end

    test "a video whose probed duration exceeds the limit is rejected after transcode, no derivatives" do
      over = fake_result(duration: 75.0) # container says ~5s, ffprobe says 75s
      stub_method(Media::VideoProcessor, :call, ->(_bytes) { over }) do
        ProcessProfileVideoJob.perform_now(@video.id)
      end

      @video.reload
      assert @video.processing_failed?
      assert_not @video.playback.attached?
    end

    test "is idempotent — a second run does not re-process or duplicate derivatives" do
      result = fake_result
      stub_method(Media::VideoProcessor, :call, ->(_bytes) { result }) do
        perform_enqueued_jobs { ProcessProfileVideoJob.perform_now(@video.id) }
        first_key = @video.reload.playback.blob.key
        processed_at = @video.processed_at

        calls = 0
        stub_method(Media::VideoProcessor, :call, ->(_bytes) { calls += 1; result }) do
          ProcessProfileVideoJob.perform_now(@video.id)
        end

        assert_equal 0, calls, "a ready video must not be re-processed"
        assert_equal first_key, @video.reload.playback.blob.key
        assert_equal processed_at.to_i, @video.processed_at.to_i
      end
    end

    test "a transcode failure is a terminal failure, not an endless retry" do
      stub_method(Media::VideoProcessor, :call, ->(_bytes) { raise Media::VideoProcessor::TranscodeFailed, "bad" }) do
        ProcessProfileVideoJob.perform_now(@video.id)
      end

      assert @video.reload.processing_failed?
      assert_not @video.deliverable?
    end

    test "a timeout is transient — the job retries then fails, never loops" do
      stub_method(Media::VideoProcessor, :call, ->(_bytes) { raise Media::VideoProcessor::TimedOut, "slow" }) do
        perform_enqueued_jobs { ProcessProfileVideoJob.perform_later(@video.id) }
        10.times do
          break if enqueued_jobs.empty?

          perform_enqueued_jobs
        end
      end

      assert_empty enqueued_jobs
      assert @video.reload.processing_failed?
    end

    test "tolerates the video being deleted mid-flight" do
      @video.update!(deleted_at: Time.current)
      result = fake_result

      assert_nothing_raised do
        stub_method(Media::VideoProcessor, :call, ->(_bytes) { result }) do
          ProcessProfileVideoJob.perform_now(@video.id)
        end
      end
      assert_not @video.reload.playback.attached?
    end
  end
end
