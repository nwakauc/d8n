module Media
  # Structural safety check for an untrusted MP4/QuickTime (ISO Base Media File
  # Format) video upload, without shelling out to ffmpeg/ffprobe — neither is
  # available in this deployment image (unlike libvips, which backs
  # Media::ImageProcessor). This is a real ISO-BMFF box walker, not a stub: it
  # parses the actual box tree, so a corrupt/truncated file or a renamed
  # non-video file is rejected on structure, not just on a spoofable extension
  # or declared Content-Type.
  #
  # What IS verified:
  #   * the file starts with a valid `ftyp` box whose brand is a recognized
  #     MP4/QuickTime brand;
  #   * every box's declared size is internally consistent (no box claims to
  #     extend past its container) — this is exactly what a truncated/corrupt
  #     upload violates;
  #   * a `moov` box exists with at least one video track (`hdlr` handler_type
  #     "vide") whose sample description names a broadly-supported codec
  #     (H.264 `avc1`/`avc3` or HEVC `hvc1`/`hev1` — the two codecs ordinary
  #     phone cameras actually produce inside MP4/MOV).
  #
  # What is NOT verified (documented gap, not silently assumed safe): full
  # semantic decode of the video stream, frame-level corruption inside `mdat`,
  # or exact browser-playback compatibility. HEVC in particular plays natively
  # in Safari/iOS but not in most Chrome/Firefox builds; D8N does not transcode
  # (no ffmpeg), so HEVC playback compatibility is client-dependent. This is
  # reported plainly rather than promised.
  class VideoContainerValidator
    Error = Class.new(StandardError)
    InvalidVideo = Class.new(Error)

    # ISO-BMFF major/compatible brands produced by iOS/Android camera apps and
    # standard MP4 muxers. `"qt  "` (QuickTime, padded to 4 bytes) is what iOS
    # gives .mov files.
    ACCEPTED_BRANDS = [ "isom", "iso2", "mp41", "mp42", "avc1", "M4V ", "M4VH", "M4VP", "qt  " ].freeze
    # Broadly-supported phone-camera codecs only — see class comment.
    ACCEPTED_VIDEO_CODECS = %w[ avc1 avc3 hvc1 hev1 ].freeze
    CONTAINER_BOXES = %w[ moov trak mdia minf stbl udta ].freeze
    # Abuse ceiling on box COUNT (not file size — that's enforced upstream by
    # Messaging::MessageAttachmentUpload). A malformed/adversarial file with
    # millions of zero-length sibling boxes could otherwise burn CPU walking
    # the tree; no legitimate encoder produces anywhere near this many boxes.
    MAX_BOXES = 5_000

    Result = Data.define(:codec, :duration_seconds)

    def self.call(bytes)
      new(bytes).call
    end

    def initialize(bytes)
      @bytes = bytes.to_s.b
      @box_count = 0
    end

    def call
      raise InvalidVideo, "empty upload" if bytes.empty?

      top_level = parse_boxes(0, bytes.bytesize)
      ftyp = top_level.first
      raise InvalidVideo, "missing ftyp box" if ftyp.nil? || ftyp[:type] != "ftyp"

      validate_brand!(ftyp)
      moov = top_level.find { |box| box[:type] == "moov" }
      raise InvalidVideo, "missing moov box" if moov.nil?

      codec = video_codec(moov)
      raise InvalidVideo, "no supported video track" if codec.nil?
      raise InvalidVideo, "unsupported video codec: #{codec.inspect}" unless ACCEPTED_VIDEO_CODECS.include?(codec)

      Result.new(codec:, duration_seconds: duration(moov))
    end

    private

    attr_reader :bytes

    def parse_boxes(start, stop)
      boxes = []
      offset = start
      while offset < stop
        @box_count += 1
        raise InvalidVideo, "too many boxes" if @box_count > MAX_BOXES

        header = read_box_header(offset, stop)
        box = { type: header[:type], body_start: header[:body_start], body_end: header[:box_end] }
        box[:children] = parse_boxes(header[:body_start], header[:box_end]) if CONTAINER_BOXES.include?(header[:type])
        boxes << box
        offset = header[:box_end]
      end
      boxes
    end

    def read_box_header(offset, stop)
      raise InvalidVideo, "truncated box header" if offset + 8 > stop

      size = read_uint32(offset)
      type = bytes[offset + 4, 4]
      header_size = 8

      if size == 1
        raise InvalidVideo, "truncated 64-bit box size" if offset + 16 > stop
        size = read_uint64(offset + 8)
        header_size = 16
      elsif size.zero?
        size = stop - offset # box extends to the end of its container
      end

      box_end = offset + size
      raise InvalidVideo, "invalid box size" if size < header_size || box_end > stop

      { type:, body_start: offset + header_size, box_end: }
    end

    def validate_brand!(ftyp)
      length = ftyp[:body_end] - ftyp[:body_start]
      raise InvalidVideo, "truncated ftyp box" if length < 8

      body = bytes[ftyp[:body_start], length].to_s
      major = body[0, 4]
      compatible = body[8..].to_s.scan(/.{4}/m)
      return if ([ major ] + compatible).any? { |brand| ACCEPTED_BRANDS.include?(brand) }

      raise InvalidVideo, "unrecognized container brand"
    end

    def find_all(boxes, type)
      Array(boxes).flat_map do |box|
        matches = box[:type] == type ? [ box ] : []
        matches + find_all(box[:children], type)
      end
    end

    def video_codec(moov)
      find_all(moov[:children], "trak").each do |trak|
        hdlr = find_all(trak[:children], "hdlr").first
        next unless hdlr && handler_type(hdlr) == "vide"

        stsd = find_all(trak[:children], "stsd").first
        next if stsd.nil?

        fourcc = sample_entry_fourcc(stsd)
        return fourcc if fourcc
      end
      nil
    end

    def handler_type(hdlr)
      # hdlr body: version/flags(4) + pre_defined(4) + handler_type(4, fourCC).
      bytes[hdlr[:body_start] + 8, 4]
    end

    def sample_entry_fourcc(stsd)
      # stsd body: version/flags(4) + entry_count(4), then the first sample
      # entry begins with size(4) + format(4, fourCC).
      body_start = stsd[:body_start]
      return nil if stsd[:body_end] - body_start < 16

      bytes[body_start + 12, 4]
    end

    # Best-effort only: duration is descriptive metadata, never a safety gate,
    # so any parse failure here yields nil rather than rejecting the upload.
    def duration(moov)
      mvhd = find_all(moov[:children], "mvhd").first
      return nil if mvhd.nil?

      base = mvhd[:body_start]
      version = bytes[base, 1]&.unpack1("C")
      if version == 1
        timescale = read_uint32(base + 20)
        raw_duration = read_uint64(base + 24)
      else
        timescale = read_uint32(base + 12)
        raw_duration = read_uint32(base + 16)
      end
      return nil if timescale.nil? || timescale.zero? || raw_duration.nil?

      (raw_duration.to_f / timescale).round(3)
    rescue StandardError
      nil
    end

    def read_uint32(offset)
      bytes[offset, 4]&.unpack1("N")
    end

    def read_uint64(offset)
      bytes[offset, 8]&.unpack1("Q>")
    end
  end
end
