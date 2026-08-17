require "vips"

module Media
  # Decodes an untrusted uploaded image and produces a safe, D8N-owned display
  # derivative: re-encoded from decoded pixels, resized to a display bound, and
  # stripped of EXIF/GPS/IPTC/XMP/ICC and every other metadata block.
  #
  # The image loader is selected from the byte signature by libvips, never from
  # the declared MIME type or filename, so a spoofed extension cannot smuggle a
  # non-image or a mismatched decoder. libvips is demand-driven, so header
  # dimensions are read cheaply before pixels are decoded, which lets us reject
  # decompression/resource-exhaustion hazards up front.
  class ImageProcessor
    Error = Class.new(StandardError)
    # Not a decodable image, or beyond safe limits — terminal, do not retry.
    InvalidImage = Class.new(Error)
    ImageTooLarge = Class.new(Error)

    MAX_SOURCE_DIMENSION = 12_000        # px on either edge
    MAX_SOURCE_PIXELS = 40_000_000       # ~40 MP decompression-bomb ceiling
    DISPLAY_MAX_DIMENSION = 1_600        # longest edge of the derivative
    JPEG_QUALITY = 82
    OUTPUT_CONTENT_TYPE = "image/jpeg"

    Result = Data.define(:bytes, :content_type, :width, :height)

    def self.call(bytes)
      new(bytes).call
    end

    def initialize(bytes)
      @bytes = bytes.to_s.b
    end

    def call
      raise InvalidImage, "empty upload" if @bytes.empty?

      image = load_image
      guard_dimensions!(image)
      image = image.autorot                 # bake EXIF orientation into pixels
      image = image.colourspace("srgb")     # normalize to sRGB
      image = downscale(image)
      image = flatten_alpha(image)          # JPEG has no alpha

      bytes = image.write_to_buffer(
        ".jpg", Q: JPEG_QUALITY, strip: true, interlace: true, optimize_coding: true
      )
      Result.new(bytes:, content_type: OUTPUT_CONTENT_TYPE, width: image.width, height: image.height)
    rescue Vips::Error
      raise InvalidImage, "undecodable image"
    end

    private

    def load_image
      Vips::Image.new_from_buffer(@bytes, "")
    rescue Vips::Error
      raise InvalidImage, "unsupported or corrupt image"
    end

    def guard_dimensions!(image)
      width = image.width
      height = image.height
      raise InvalidImage, "non-positive dimensions" unless width.positive? && height.positive?
      return unless width > MAX_SOURCE_DIMENSION || height > MAX_SOURCE_DIMENSION ||
        (width.to_i * height.to_i) > MAX_SOURCE_PIXELS

      raise ImageTooLarge, "source image exceeds processing limits"
    end

    def downscale(image)
      longest = [ image.width, image.height ].max
      return image if longest <= DISPLAY_MAX_DIMENSION

      image.resize(DISPLAY_MAX_DIMENSION.to_f / longest)
    end

    def flatten_alpha(image)
      image.has_alpha? ? image.flatten(background: [ 255, 255, 255 ]) : image
    end
  end
end
