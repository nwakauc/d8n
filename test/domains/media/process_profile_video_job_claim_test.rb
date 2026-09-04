# frozen_string_literal: true

require "test_helper"

module Media
  # Claim-token / stale-reclaim / ABA hardening for ProcessProfileVideoJob
  # (ADR 0029 Pass 2B) — video analogue of ProcessProfilePhotoJobClaimTest.
  class ProcessProfileVideoJobClaimTest < ActiveJob::TestCase
    setup do
      @brand = Brand.create!(slug: "date9ja", name: "Date9ja")
      @user = User.create!
      @membership = BrandMembership.create!(brand: @brand, user: @user)
      @profile = Profile.create!(brand: @brand, user: @user, brand_membership: @membership,
        display_name: "Ada", birthdate: 26.years.ago.to_date, gender: "woman")
      @raw = build_test_h264_mp4_bytes(duration: 1)
      @service = ActiveStorage::Blob.service.name.to_s
      @video = attach_raw_video(@profile, @user)
    end

    # Migration-style raw key so Media::ObjectKey.derived_key swaps `original.mp4`
    # for `playback.mp4` / `poster.jpg` in the SAME folder (matching real Pass-2A).
    def attach_raw_video(profile, user)
      key = "migrations/media/v3/date9ja/profile_video_original/#{SecureRandom.uuid}/original.mp4"
      raw = ActiveStorage::Blob.create_and_upload!(io: StringIO.new(@raw), key:,
        filename: "original.mp4", content_type: "video/mp4", service_name: @service)
      video = ProfileVideo.new(profile:, user:, brand: @brand, status: :pending_review, visibility: :visible)
      video.video.attach(raw)
      video.save!
      video
    end

    def fake_result
      Media::VideoProcessor::Result.new(rendition_bytes: @raw, transcoded: false,
        poster_bytes: build_test_jpeg_bytes, width: 64, height: 64, duration_seconds: 1.0)
    end

    test "a recent processing claim is left alone (in_progress) — a duplicate runner does no work" do
      @video.update!(processing_state: :processing, processing_started_at: 10.seconds.ago,
        processing_claim_token: SecureRandom.uuid)
      calls = 0
      result = fake_result
      stub_method(Media::VideoProcessor, :call, ->(_b) { calls += 1; result }) do
        ProcessProfileVideoJob.perform_now(@video.id)
      end
      assert_equal 0, calls
      assert @video.reload.processing_processing?
    end

    test "a stale processing claim is reclaimed and completed" do
      stale_token = SecureRandom.uuid
      @video.update!(processing_state: :processing,
        processing_started_at: (ProfileVideo::STALE_PROCESSING_AFTER + 1.minute).ago,
        processing_claim_token: stale_token)

      result = fake_result
      stub_method(Media::VideoProcessor, :call, ->(_b) { result }) do
        perform_enqueued_jobs { ProcessProfileVideoJob.perform_now(@video.id) }
      end

      @video.reload
      assert @video.processing_ready?
      assert_nil @video.processing_claim_token
      assert @video.playback.attached?
      assert @video.poster.attached?
    end

    test "a terminal failure is never re-processed" do
      @video.update!(processing_state: :failed, metadata: { "processing_failure_kind" => "terminal" })
      calls = 0
      result = fake_result
      stub_method(Media::VideoProcessor, :call, ->(_b) { calls += 1; result }) do
        ProcessProfileVideoJob.perform_now(@video.id)
      end
      assert_equal 0, calls
      assert @video.reload.processing_failed?
    end

    test "ABA: a stale worker that wakes after a reclaim cannot finalize" do
      current_token = SecureRandom.uuid
      stale = ProcessProfileVideoJob.new
      stale.instance_variable_set(:@token, SecureRandom.uuid) # a DIFFERENT (stale) token
      @video.update!(processing_state: :processing, processing_started_at: Time.current,
        processing_claim_token: current_token)

      # The stale worker tries to finalize with its old token.
      stale.send(:finalize!, @video.id, fake_result)

      @video.reload
      assert @video.processing_processing?, "state untouched by the stale worker"
      assert_equal current_token, @video.processing_claim_token
      refute @video.playback.attached?
    end

    test "processing_sweepable covers pending / retryable-failed / stale, never ready or terminal" do
      pending = @video
      ready = make_video(state: :ready)
      terminal = make_video(state: :failed, metadata: { "processing_failure_kind" => "terminal" })
      retryable = make_video(state: :failed)
      stale = make_video(state: :processing, started_at: 30.minutes.ago, token: SecureRandom.uuid)
      recent = make_video(state: :processing, started_at: 10.seconds.ago, token: SecureRandom.uuid)

      sweepable = ProfileVideo.processing_sweepable.to_a
      assert_includes sweepable, pending
      assert_includes sweepable, retryable
      assert_includes sweepable, stale
      assert_not_includes sweepable, ready
      assert_not_includes sweepable, terminal
      assert_not_includes sweepable, recent
    end

    test "the sweeper enqueues exactly the sweepable rows" do
      make_video(state: :ready)
      stale = make_video(state: :processing, started_at: 30.minutes.ago, token: SecureRandom.uuid)

      result = nil
      assert_enqueued_jobs 2, only: ProcessProfileVideoJob do
        result = Media::ProfileVideoProcessingSweeper.call
      end
      assert_equal 2, result.enqueued # @video (pending) + stale
    end

    def make_video(state:, started_at: nil, token: nil, metadata: {})
      user = User.create!
      m = BrandMembership.create!(brand: @brand, user:)
      profile = Profile.create!(brand: @brand, user:, brand_membership: m,
        display_name: "P#{user.id}", birthdate: 28.years.ago.to_date, gender: "man")
      v = ProfileVideo.new(profile:, user:, brand: @brand, status: :approved, visibility: :visible)
      v.video.attach(io: StringIO.new(@raw), filename: "v.mp4", content_type: "video/mp4")
      v.save!
      v.update!(processing_state: state, processing_started_at: started_at,
        processing_claim_token: token, metadata:)
      v
    end
  end
end
