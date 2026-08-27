require "test_helper"

module Media
  class VideoContainerValidatorTest < ActiveSupport::TestCase
    test "accepts a well-formed H.264 MP4 and extracts codec and duration" do
      bytes = build_test_mp4_bytes(codec: "avc1", duration_units: 5000, timescale: 1000)

      result = VideoContainerValidator.call(bytes)

      assert_equal "avc1", result.codec
      assert_in_delta 5.0, result.duration_seconds, 0.001
    end

    test "accepts HEVC as a recognized broadly-produced phone codec" do
      result = VideoContainerValidator.call(build_test_mp4_bytes(codec: "hvc1"))
      assert_equal "hvc1", result.codec
    end

    test "accepts the QuickTime (.mov) brand" do
      result = VideoContainerValidator.call(build_test_mp4_bytes(brand: "qt  "))
      assert_equal "avc1", result.codec
    end

    test "rejects an unsupported codec even inside a structurally valid container" do
      error = assert_raises(VideoContainerValidator::InvalidVideo) do
        VideoContainerValidator.call(build_test_mp4_bytes(codec: "vp09"))
      end
      assert_match(/unsupported video codec/, error.message)
    end

    test "rejects an unrecognized container brand" do
      box = ->(type, body) { [ body.bytesize + 8 ].pack("N") + type + body }
      ftyp = box.call("ftyp", "xxxx" + [ 0 ].pack("N") + "xxxxyyyy")
      mdat = box.call("mdat", "x" * 32)

      assert_raises(VideoContainerValidator::InvalidVideo) { VideoContainerValidator.call(ftyp + mdat) }
    end

    test "rejects an empty upload" do
      assert_raises(VideoContainerValidator::InvalidVideo) { VideoContainerValidator.call("") }
    end

    test "rejects arbitrary non-video bytes (e.g. a renamed executable)" do
      assert_raises(VideoContainerValidator::InvalidVideo) do
        VideoContainerValidator.call("MZ\x90\x00" + ("\x00" * 200))
      end
    end

    test "rejects a truncated/corrupt upload" do
      good = build_test_mp4_bytes
      assert_raises(VideoContainerValidator::InvalidVideo) do
        VideoContainerValidator.call(good[0, good.bytesize - 10])
      end
    end

    test "rejects a file missing the moov box" do
      box = ->(type, body) { [ body.bytesize + 8 ].pack("N") + type + body }
      ftyp = box.call("ftyp", "isom" + [ 0 ].pack("N") + "isomiso2mp41")
      mdat = box.call("mdat", "x" * 32)

      assert_raises(VideoContainerValidator::InvalidVideo) { VideoContainerValidator.call(ftyp + mdat) }
    end

    test "rejects a video track whose handler is not vide (e.g. audio-only)" do
      box = ->(type, body) { [ body.bytesize + 8 ].pack("N") + type + body }
      ftyp = box.call("ftyp", "isom" + [ 0 ].pack("N") + "isomiso2mp41")
      mvhd = box.call("mvhd", [ 0 ].pack("N") + ("\x00" * 8) + [ 1000 ].pack("N") + [ 1000 ].pack("N") + ("\x00" * 60))
      hdlr = box.call("hdlr", [ 0 ].pack("N") + [ 0 ].pack("N") + "soun" + ("\x00" * 12))
      sample_entry = [ 20 ].pack("N") + "mp4a" + ("\x00" * 12)
      stsd = box.call("stsd", [ 0 ].pack("N") + [ 1 ].pack("N") + sample_entry)
      stbl = box.call("stbl", stsd)
      minf = box.call("minf", stbl)
      mdia = box.call("mdia", hdlr + minf)
      trak = box.call("trak", mdia)
      moov = box.call("moov", mvhd + trak)

      assert_raises(VideoContainerValidator::InvalidVideo) { VideoContainerValidator.call(ftyp + moov) }
    end

    test "a pathological box storm hits the box-count abuse ceiling" do
      box = ->(type, body) { [ body.bytesize + 8 ].pack("N") + type + body }
      ftyp = box.call("ftyp", "isom" + [ 0 ].pack("N") + "isomiso2mp41")
      storm = (VideoContainerValidator::MAX_BOXES + 10).times.map { box.call("free", "") }.join

      assert_raises(VideoContainerValidator::InvalidVideo) { VideoContainerValidator.call(ftyp + storm) }
    end
  end
end
