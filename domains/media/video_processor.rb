require "open3"
require "json"
require "tempfile"

module Media
  # Turns a validated chat-video original into a browser/mobile-compatible
  # H.264 + AAC MP4 playback rendition and a poster frame, by shelling out to
  # `ffmpeg`/`ffprobe` (see Dockerfile — installed the same way libvips already
  # is for Media::ImageProcessor). Every invocation runs as an argv ARRAY via
  # Open3, never a shell string, so nothing in an untrusted video file can ever
  # be interpreted as shell syntax.
  #
  # "Do not transcode unnecessarily": ffprobe determines the REAL video/audio
  # codecs and container. If the video is already H.264 + (AAC or silent) in an
  # MP4-family container, no ffmpeg invocation happens at all — the rendition
  # IS the original bytes, byte-identical, zero extra compute or storage. If
  # only the container needs to change (e.g. a .mov already holding H.264/AAC),
  # ffmpeg does a fast stream copy (`-c copy`), never a re-encode. Only a
  # genuinely incompatible codec (HEVC, etc.) triggers a real transcode.
  class VideoProcessor
    Error = Class.new(StandardError)
    ProbeFailed = Class.new(Error)
    TranscodeFailed = Class.new(Error)
    PosterFailed = Class.new(Error)
    # Distinct from the failures above: a wall-clock ceiling was hit, not a
    # decode/encode failure. The caller (Media::ProcessMessageAttachmentJob)
    # treats this as TRANSIENT and retries — a busy worker node, not the file
    # itself, is the likely cause.
    TimedOut = Class.new(Error)

    TARGET_VIDEO_CODEC = "h264"
    TARGET_AUDIO_CODEC = "aac"
    TARGET_CONTAINER = "mp4"

    # Wall-clock ceilings per ffmpeg/ffprobe invocation. These are TECHNICAL
    # abuse/worker-protection ceilings (guarding Solid Queue capacity against a
    # pathological file that makes ffmpeg spin, e.g. a decoder edge case), not
    # a product-facing video DURATION limit — an ordinary phone video transcodes
    # in well under a minute. See MessageAttachmentUpload's 750MB byte-size
    # ceiling for the identical rationale applied to file size instead of time.
    PROBE_TIMEOUT = 30
    TRANSCODE_TIMEOUT = 10 * 60
    POSTER_TIMEOUT = 30
    POSTER_SEEK_SECONDS = 1.0

    Result = Data.define(:rendition_bytes, :transcoded, :poster_bytes, :width, :height, :duration_seconds)

    def self.call(bytes)
      new(bytes).call
    end

    def initialize(bytes)
      @bytes = bytes.to_s.b
    end

    def call
      Tempfile.create([ "d8n-video-in", ".bin" ], binmode: true) do |input|
        input.write(@bytes)
        input.flush

        probe = probe!(input.path)
        plan = transcode_plan(probe)
        rendition_bytes = plan.fetch(:needed) ? transcode!(input.path, plan) : @bytes
        poster_bytes = extract_poster!(input.path, probe)

        Result.new(
          rendition_bytes:, transcoded: plan.fetch(:needed), poster_bytes:,
          width: probe.dig(:video, :width), height: probe.dig(:video, :height),
          duration_seconds: probe[:duration]
        )
      end
    end

    private

    def probe!(path)
      stdout, _stderr, status = run(
        %w[ ffprobe -v error -print_format json -show_format -show_streams ] + [ path ],
        timeout: PROBE_TIMEOUT
      )
      raise ProbeFailed, "ffprobe exit=#{status&.exitstatus.inspect}" unless status&.success?

      parsed = JSON.parse(stdout)
      video_stream = Array(parsed["streams"]).find { |stream| stream["codec_type"] == "video" }
      audio_stream = Array(parsed["streams"]).find { |stream| stream["codec_type"] == "audio" }
      raise ProbeFailed, "no video stream" if video_stream.nil?

      {
        # ffprobe's `format_name` for the whole ISO-BMFF family is the literal
        # string "mov,mp4,m4a,3gp,3g2,mj2" for EVERY member — it cannot
        # distinguish an actual .mp4 from a sibling .mov. `format.tags.major_brand`
        # is the real discriminator (exactly the `ftyp` major brand
        # Media::VideoContainerValidator already reads): "isom"/"mp4x" family for
        # MP4, "qt  " for QuickTime/.mov.
        major_brand: parsed.dig("format", "tags", "major_brand").to_s.strip,
        duration: parsed.dig("format", "duration")&.to_f,
        video: { codec: video_stream["codec_name"].to_s, width: video_stream["width"], height: video_stream["height"] },
        audio: audio_stream && { codec: audio_stream["codec_name"].to_s }
      }
    rescue JSON::ParserError => e
      raise ProbeFailed, "unparseable ffprobe output: #{e.class}"
    end

    # A brand actually meaning "this file already IS an MP4", not merely
    # "MP4-compatible" (QuickTime's "qt  " is MP4-compatible but is NOT MP4 —
    # most browsers other than Safari refuse a video/quicktime container even
    # when its codecs are already H.264/AAC, which is exactly why "MOV input
    # producing compatible playback" needs a real re-mux, not a skip).
    MP4_CONTAINER_BRANDS = %w[ isom iso2 mp41 mp42 avc1 M4V M4VH M4VP ].freeze

    def transcode_plan(probe)
      video_ok = probe.dig(:video, :codec) == TARGET_VIDEO_CODEC
      audio_ok = probe[:audio].nil? || probe.dig(:audio, :codec) == TARGET_AUDIO_CODEC
      container_ok = MP4_CONTAINER_BRANDS.include?(probe[:major_brand])

      { needed: !(video_ok && audio_ok && container_ok), video_ok:, audio_ok: }
    end

    def transcode!(input_path, plan)
      Tempfile.create([ "d8n-video-out", ".mp4" ], binmode: true) do |output|
        output.close
        args = [
          "ffmpeg", "-y", "-i", input_path,
          "-c:v", plan.fetch(:video_ok) ? "copy" : "libx264",
          *(plan.fetch(:video_ok) ? [] : %w[ -preset veryfast -crf 23 ]),
          "-c:a", plan.fetch(:audio_ok) ? "copy" : "aac",
          "-movflags", "+faststart",
          output.path
        ]
        _stdout, _stderr, status = run(args, timeout: TRANSCODE_TIMEOUT)
        raise TranscodeFailed, "ffmpeg exit=#{status&.exitstatus.inspect}" unless status&.success?

        bytes = File.binread(output.path)
        raise TranscodeFailed, "empty transcode output" if bytes.empty?

        bytes
      end
    end

    def extract_poster!(input_path, probe)
      duration = probe[:duration]
      seek = duration.present? ? [ POSTER_SEEK_SECONDS, duration / 2 ].min : 0
      Tempfile.create([ "d8n-poster", ".jpg" ], binmode: true) do |output|
        output.close
        args = [ "ffmpeg", "-y", "-ss", seek.to_s, "-i", input_path, "-frames:v", "1", "-q:v", "2", output.path ]
        _stdout, _stderr, status = run(args, timeout: POSTER_TIMEOUT)
        raise PosterFailed, "ffmpeg exit=#{status&.exitstatus.inspect}" unless status&.success?

        bytes = File.binread(output.path)
        raise PosterFailed, "empty poster output" if bytes.empty?

        bytes
      end
    end

    # Runs an argv array directly — never a shell string — with a hard
    # wall-clock ceiling. stdout/stderr are drained on separate threads so a
    # verbose ffmpeg (it logs progress to stderr) can never deadlock against
    # an unread pipe. On timeout the process is SIGKILLed rather than left to
    # run to completion, so a pathological input can never pin a worker
    # indefinitely.
    def run(args, timeout:)
      Open3.popen3(*args) do |stdin, stdout, stderr, wait_thr|
        stdin.close
        stdout_reader = Thread.new { stdout.read }
        stderr_reader = Thread.new { stderr.read }

        unless wait_thr.join(timeout)
          Process.kill("KILL", wait_thr.pid)
          wait_thr.join
          stdout_reader.kill
          stderr_reader.kill
          raise TimedOut, "#{args.first} exceeded #{timeout}s"
        end

        [ stdout_reader.value, stderr_reader.value, wait_thr.value ]
      end
    rescue Errno::ENOENT => e
      raise Error, "#{args.first} is not available: #{e.message}"
    end
  end
end
