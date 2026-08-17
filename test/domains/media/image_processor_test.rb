require "test_helper"
require "vips"
require_relative "../../support/exif_jpeg"

module Media
  class ImageProcessorTest < ActiveSupport::TestCase
    test "re-encodes a valid JPEG into a JPEG derivative that decodes" do
      raw = Vips::Image.black(300, 200).add([ 90 ]).cast("uchar").write_to_buffer(".jpg")

      result = ImageProcessor.call(raw)

      assert_equal "image/jpeg", result.content_type
      decoded = Vips::Image.new_from_buffer(result.bytes, "")
      assert_equal 300, decoded.width
      assert_equal 200, decoded.height
      refute_equal raw, result.bytes, "derivative must be re-encoded, not the original bytes"
    end

    test "flattens a transparent PNG onto an opaque JPEG" do
      png = Vips::Image.black(64, 64).add([ 10 ]).cast("uchar")
      png = png.bandjoin(Vips::Image.black(64, 64).add([ 128 ]).cast("uchar")) # add alpha band
      raw = png.copy(interpretation: :"b-w").write_to_buffer(".png")

      result = ImageProcessor.call(raw)

      decoded = Vips::Image.new_from_buffer(result.bytes, "")
      assert_equal "image/jpeg", result.content_type
      refute decoded.has_alpha?, "JPEG derivative must have no alpha channel"
    end

    test "downscales an oversized display image to the display bound" do
      raw = Vips::Image.black(4000, 2000).add([ 50 ]).cast("uchar").write_to_buffer(".jpg")

      result = ImageProcessor.call(raw)

      decoded = Vips::Image.new_from_buffer(result.bytes, "")
      assert_equal ImageProcessor::DISPLAY_MAX_DIMENSION, [ decoded.width, decoded.height ].max
    end

    test "rejects non-image bytes as a terminal invalid image (ignores any declared type)" do
      assert_raises ImageProcessor::InvalidImage do
        ImageProcessor.call("this is definitely not an image, whatever the extension claims")
      end
    end

    test "rejects empty input" do
      assert_raises ImageProcessor::InvalidImage do
        ImageProcessor.call("")
      end
    end

    test "rejects a decompression-bomb-sized source" do
      raw = Vips::Image.black(ImageProcessor::MAX_SOURCE_DIMENSION + 1, 4).write_to_buffer(".png")

      assert_raises ImageProcessor::ImageTooLarge do
        ImageProcessor.call(raw)
      end
    end

    test "strips EXIF and GPS metadata from the generated derivative" do
      raw = ExifJpeg.with_gps

      # Premise: the raw input genuinely carries GPS EXIF (libvips parses it).
      raw_image = Vips::Image.new_from_buffer(raw, "")
      assert_includes raw_image.get_fields, "exif-ifd3-GPSLatitude"
      assert raw.include?("Exif"), "raw fixture must contain an EXIF marker"

      result = ImageProcessor.call(raw)

      # Proof by inspecting the actual output, not by trusting a method call.
      refute result.bytes.include?("Exif"), "derivative must not contain an EXIF marker"
      refute result.bytes.include?("\xFF\xE1".b), "derivative must not contain an APP1 metadata segment"
      derivative = Vips::Image.new_from_buffer(result.bytes, "")
      assert_empty derivative.get_fields.grep(/gps/i), "derivative must expose no GPS fields"
      assert_empty derivative.get_fields.grep(/exif/i), "derivative must expose no EXIF fields"
    end
  end
end
