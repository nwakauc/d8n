# frozen_string_literal: true

require "test_helper"
require "vips"

module Migration
  module MediaTransfer
    # ADR 0029 — the injected media-kind strategy. MediaKind::Image must reproduce
    # the pre-0029 Profile Photo behaviour exactly; MediaKind::Video parameterizes
    # only the genuinely media-specific concerns.
    class MediaKindTest < ActiveSupport::TestCase
      Image = MediaKind::Image
      Video = MediaKind::Video

      def jpeg = Vips::Image.black(40, 30).add([ 90 ]).cast("uchar").write_to_buffer(".jpg").b
      def png = Vips::Image.black(20, 20).write_to_buffer(".png").b

      # --- Image: unchanged Profile Photo semantics -----------------------

      test "Image accepts only jpeg/png/webp and keeps the accepted reason code" do
        assert_equal %w[image/jpeg image/png image/webp], Image.content_types
        assert_equal 8.megabytes, Image.byte_ceiling
        assert_equal "not_an_image", Image.not_recognized_reason
      end

      test "Image.detect_type reads magic bytes, never the declared type" do
        assert_equal "image/jpeg", Image.detect_type(jpeg)
        assert_equal "image/png", Image.detect_type(png)
        assert_nil Image.detect_type("MZ not an image".b)
      end

      test "Image.structural_verify! passes a real image and returns empty facts" do
        facts = Image.structural_verify!(jpeg)
        assert_nil facts.duration_seconds
      end

      test "Image.structural_verify! raises validation_failed/malformed_image on a broken image" do
        error = assert_raises(MediaKind::StructuralError) do
          Image.structural_verify!("\xFF\xD8\xFF".b + ("garbage" * 20))
        end
        assert_equal :validation_failed, error.disposition
        assert_equal "malformed_image", error.reason
      end

      test "Image.structural_verify! honours an injected image_processor" do
        stub = Class.new do
          def self.call(_) = raise Media::ImageProcessor::Error, "boom"
        end
        assert_raises(MediaKind::StructuralError) { Image.structural_verify!(jpeg, image_processor: stub) }
      end

      # --- Video ---------------------------------------------------------

      test "Video accepts only mp4/quicktime and carries the brand byte ceiling" do
        assert_equal %w[video/mp4 video/quicktime], Video.content_types
        assert_equal Media::VideoPolicy::DEFAULT_MAX_BYTE_SIZE, Video.byte_ceiling
      end

      test "Video.detect_type sniffs the ISO-BMFF ftyp brand" do
        assert_equal "video/mp4", Video.detect_type(build_test_mp4_bytes(brand: "isom"))
        assert_equal "video/quicktime", Video.detect_type(build_test_mp4_bytes(brand: "qt  "))
        assert_nil Video.detect_type("not a video".b)
        assert_nil Video.detect_type(jpeg)
      end

      test "Video.detect_type distinguishes a real .mov from a real .mp4" do
        assert_equal "video/mp4", Video.detect_type(build_test_h264_mp4_bytes(duration: 1))
        assert_equal "video/quicktime", Video.detect_type(build_test_h264_mov_bytes(duration: 1))
      end

      test "Video.structural_verify! derives authoritative duration for a real H.264 MP4" do
        facts = Video.structural_verify!(build_test_h264_mp4_bytes(duration: 2))
        assert_in_delta 2.0, facts.duration_seconds, 0.3
        assert_equal "avc1", facts.codec
      end

      test "Video.structural_verify! fails closed quarantined/duration_unreadable when duration is unreadable" do
        error = assert_raises(MediaKind::StructuralError) { Video.structural_verify!(build_test_mp4_bytes) }
        assert_equal :quarantined, error.disposition
        assert_equal "duration_unreadable", error.reason
      end

      test "Video.structural_verify! fails closed validation_failed/malformed_container on a corrupt container" do
        good = build_test_h264_mp4_bytes(duration: 1)
        error = assert_raises(MediaKind::StructuralError) { Video.structural_verify!(good[0, good.bytesize - 40]) }
        assert_equal :validation_failed, error.disposition
        assert_equal "malformed_container", error.reason
      end

      test "Video.structural_verify! fails closed on an ffprobe timeout" do
        stub_method(Media::VideoProcessor, :probe, ->(_) { raise Media::VideoProcessor::TimedOut, "slow" }) do
          error = assert_raises(MediaKind::StructuralError) do
            Video.structural_verify!(build_test_h264_mp4_bytes(duration: 1))
          end
          assert_equal "duration_unreadable", error.reason
        end
      end

      test "Video.remote_reverify! re-validates the container only (no ffprobe)" do
        assert_nil Video.remote_reverify!(build_test_mp4_bytes)
        assert_raises(MediaKind::StructuralError) { Video.remote_reverify!("nope".b) }
      end

      test "DEFAULT is Image so existing callers are unchanged" do
        assert_equal MediaKind::Image, MediaKind::DEFAULT
      end
    end
  end
end
