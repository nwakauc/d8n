# frozen_string_literal: true

require "test_helper"

module Media
  # The single authoritative "valid completed ProfileVideo playback + poster
  # derivative pair" contract (ADR 0029 Pass 2B) — video analogue of
  # Media::DisplayDerivativeTest.
  class PlaybackDerivativeTest < ActiveSupport::TestCase
    setup do
      @brand = Brand.create!(slug: "date9ja", name: "Date9ja")
      @user = User.create!
      @membership = BrandMembership.create!(brand: @brand, user: @user)
      @profile = Profile.create!(brand: @brand, user: @user, brand_membership: @membership,
        display_name: "Ada", birthdate: 26.years.ago.to_date, gender: "woman")
      @service = ActiveStorage::Blob.service.name.to_s
      @playback_key = "migrations/media/v3/date9ja/profile_video_original/#{SecureRandom.uuid}/playback.mp4"
      @poster_key = @playback_key.sub("playback.mp4", "poster.jpg")
      @video = build_ready_video
    end

    def build_ready_video
      video = ProfileVideo.new(profile: @profile, user: @user, brand: @brand,
        status: :approved, visibility: :visible)
      raw_key = @playback_key.sub("playback.mp4", "original.mp4")
      raw = ActiveStorage::Blob.create_and_upload!(io: StringIO.new(build_test_h264_mp4_bytes(duration: 1)),
        key: raw_key, filename: "original.mp4", content_type: "video/mp4", service_name: @service)
      video.video.attach(raw)
      video.save!

      playback = ActiveStorage::Blob.create_and_upload!(io: StringIO.new(build_test_h264_mp4_bytes(duration: 1)),
        key: @playback_key, filename: "playback.mp4", content_type: "video/mp4", service_name: @service)
      poster = ActiveStorage::Blob.create_and_upload!(io: StringIO.new(build_test_jpeg_bytes),
        key: @poster_key, filename: "poster.jpg", content_type: "image/jpeg", service_name: @service)
      video.playback.attach(playback)
      video.poster.attach(poster)
      video.update!(processing_state: :ready)
      video.reload
    end

    def valid?(**over)
      PlaybackDerivative.valid?(
        video: @video, expected_playback_key: @playback_key, expected_poster_key: @poster_key,
        expected_service: @service, **over
      )
    end

    test "true only for the exact deterministic playback + poster pair" do
      assert valid?
    end

    test "false for a wrong playback key" do
      refute PlaybackDerivative.valid?(video: @video, expected_playback_key: "#{@playback_key}x",
        expected_poster_key: @poster_key, expected_service: @service)
    end

    test "false for the wrong service" do
      refute PlaybackDerivative.valid?(video: @video, expected_playback_key: @playback_key,
        expected_poster_key: @poster_key, expected_service: "brand_test")
    end

    test "false when the playback object is missing remotely" do
      @video.playback.blob.service.delete(@playback_key)
      refute valid?
    end

    test "false when the poster object is missing remotely" do
      @video.poster.blob.service.delete(@poster_key)
      refute valid?
    end

    test "false when the playback bytes are a non-container" do
      @video.playback.blob.service.upload(@playback_key, StringIO.new("not an mp4".b))
      refute valid?
    end

    test "false when the poster bytes are not a decodable image" do
      @video.poster.blob.service.upload(@poster_key, StringIO.new("not a jpeg".b))
      refute valid?
    end

    test "false when playback is not attached" do
      @video.playback.detach
      refute PlaybackDerivative.valid?(video: @video.reload, expected_playback_key: @playback_key,
        expected_poster_key: @poster_key, expected_service: @service)
    end

    test "false when poster is not attached" do
      @video.poster.detach
      refute PlaybackDerivative.valid?(video: @video.reload, expected_playback_key: @playback_key,
        expected_poster_key: @poster_key, expected_service: @service)
    end

    test "false when the playback blob checksum no longer matches the bytes" do
      @video.playback.blob.update_columns(checksum: Digest::MD5.base64digest("other"))
      refute valid?
    end
  end
end
