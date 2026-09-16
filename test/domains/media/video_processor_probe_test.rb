# frozen_string_literal: true

require "test_helper"

module Media
  # Media::VideoProcessor.probe — the thin ffprobe-only authoritative probe
  # extracted for the migration Phase-A duration gate (ADR 0029 §7). No
  # transcode, no derivative, no upload, no ProfileVideo mutation.
  class VideoProcessorProbeTest < ActiveSupport::TestCase
    test "derives authoritative duration and codec facts from a real H.264 MP4" do
      probe = VideoProcessor.probe(build_test_h264_mp4_bytes(duration: 2))

      assert_instance_of VideoProcessor::Probe, probe
      assert_in_delta 2.0, probe.duration_seconds, 0.3
      assert_equal "h264", probe.video_codec
      assert_equal 64, probe.width
    end

    test "reads a real QuickTime (.mov) container" do
      probe = VideoProcessor.probe(build_test_h264_mov_bytes(duration: 1))
      assert_operator probe.duration_seconds, :>, 0
    end

    test "yields no parseable duration for a structurally-shaped but undecodable MP4" do
      # build_test_mp4_bytes has real box headers but fake sample data — ffprobe
      # reports a stream but no format.duration. The caller (MediaKind::Video)
      # treats a nil/<=0 duration as duration_unreadable and fails closed.
      probe = VideoProcessor.probe(build_test_mp4_bytes)
      assert_nil probe.duration_seconds
    end

    test "fails closed on arbitrary non-video bytes" do
      assert_raises(VideoProcessor::Error) { VideoProcessor.probe("not a video at all".b) }
    end

    test "fails closed when ffprobe is unavailable" do
      original = ENV["PATH"]
      ENV["PATH"] = "/nonexistent"
      assert_raises(VideoProcessor::Error) { VideoProcessor.probe(build_test_mp4_bytes) }
    ensure
      ENV["PATH"] = original
    end

    test "does not create ProfileVideo, blobs, or attachments" do
      assert_no_difference([
        -> { ProfileVideo.count }, -> { ActiveStorage::Blob.count }, -> { ActiveStorage::Attachment.count }
      ]) do
        VideoProcessor.probe(build_test_h264_mp4_bytes(duration: 1))
      end
    end
  end
end
