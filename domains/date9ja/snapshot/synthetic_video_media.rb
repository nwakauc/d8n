# frozen_string_literal: true

require "open3"
require "json"
require "digest"
require "fileutils"
require "tempfile"

module Date9ja
  module Snapshot
    # Deterministic synthetic VIDEO corpus for the Date9ja profile-video Pass 2
    # L2 rehearsal (ADR 0029 Pass 2C). The video analogue of
    # Date9ja::Snapshot::SyntheticMedia.
    #
    #   raw production backup
    #     -> date9ja_snapshot_sanitized                     (operator, PII-stripped)
    #     -> date9ja_snapshot_sanitized_media_v3             (TEMPLATE copy of the above)
    #     -> synthetic video corpus  (THIS module: bytes + manifest, patches
    #        media_v3 blob byte_size/checksum to match)
    #     -> Date9ja::Storage::LocalCorpusReader             (rehearsal transport)
    #     -> Pass 1 -> Pass 2A -> Pass 2B
    #
    # NON-NEGOTIABLE EVIDENCE RULE: the sanitized snapshot has metadata for the
    # legacy ProfileVideo records but does NOT contain their media bodies. This
    # corpus is engineering rehearsal material only. It does NOT prove anything
    # about the real legacy videos' duration, codec or container — those remain
    # UNKNOWN until an authorized real-media rehearsal.
    #
    # Every body is a genuine, structurally valid, ffmpeg-encoded H.264 MP4 or
    # QuickTime file whose parameters are a pure function of
    # (generator version, seed, source_blob_id, canonical_content_type):
    #   - deterministic duration, strictly in HAPPY_PATH_DURATION_RANGE and
    #     always <= Media::VideoPolicy DEFAULT_MAX_DURATION_SECONDS (60);
    #   - deterministic dimensions / frame rate / GOP / tone frequency;
    #   - bitexact encode (`-fflags +bitexact`, `-x264-params bitexact=1`,
    #     `-map_metadata -1`) so two clean generations are byte-identical in a
    #     fixed ffmpeg/libx264 build.
    module SyntheticVideoMedia
      GENERATOR_VERSION = "date9ja-synthetic-video-media-v1"
      DEFAULT_SEED = "date9ja-video-media-v3-2026-09-04"

      PARENT_ARTIFACT = "date9ja_snapshot_sanitized"
      ARTIFACT_NAME = "date9ja_snapshot_sanitized_media_v3"

      VIDEO_RECORD_TYPE = "ProfileVideo"
      VIDEO_ATTACHMENT_NAME = "video"

      # canonical content type -> (ffmpeg muxer, file extension). Both are real
      # ISO-BMFF the shared Media::VideoContainerValidator structurally walks.
      FORMATS = {
        "video/mp4" => { muxer: "mp4", ext: ".mp4" },
        "video/quicktime" => { muxer: "mov", ext: ".mov" }
      }.freeze

      # Happy-path durations: deterministic, all comfortably <= the 60s brand
      # limit so the WHOLE pipeline (adopt -> bind -> process -> playback +
      # poster -> ready) can be exercised. Does NOT imply the real legacy videos
      # are within range.
      HAPPY_PATH_DURATION_RANGE = (2..8)
      MAX_DURATION_SECONDS = Media::VideoPolicy::DEFAULT_MAX_DURATION_SECONDS # 60
      BYTE_CEILING = Media::VideoPolicy::DEFAULT_MAX_BYTE_SIZE # 50 MB — synthetic bodies are ~100-400 KB

      DIMENSIONS = [ [ 176, 144 ], [ 192, 144 ], [ 240, 160 ], [ 256, 144 ], [ 320, 240 ] ].freeze
      FRAME_RATES = [ 10, 12, 15 ].freeze

      # ffmpeg wall-clock ceiling per synthetic render (abuse guard, not product).
      RENDER_TIMEOUT = 120

      class RenderError < StandardError; end

      module_function

      # The deterministic render plan for one source blob. Pure — no I/O.
      def plan(source_blob_id:, canonical_content_type:, seed: DEFAULT_SEED)
        unless FORMATS.key?(canonical_content_type)
          raise ArgumentError, "unsupported canonical content type #{canonical_content_type.inspect}"
        end

        material = "#{GENERATOR_VERSION}|#{seed}|#{source_blob_id}|#{canonical_content_type}"
        d = Digest::SHA256.digest(material).unpack("Q>*") # 4 x 64-bit words

        span = HAPPY_PATH_DURATION_RANGE.size
        duration = HAPPY_PATH_DURATION_RANGE.begin + (d[0] % span)
        width, height = DIMENSIONS[d[1] % DIMENSIONS.size]
        rate = FRAME_RATES[d[2] % FRAME_RATES.size]
        frequency = 220 + (d[3] % 440)

        {
          source_blob_id: source_blob_id.to_s,
          canonical_content_type:,
          container: FORMATS.fetch(canonical_content_type)[:muxer],
          duration_seconds: duration,
          width:, height:, frame_rate: rate, tone_frequency: frequency,
          gop: rate, video_codec: "h264",
          generator_version: GENERATOR_VERSION, seed: seed.to_s
        }
      end

      # Deterministic video bytes for one source blob.
      def render(source_blob_id:, canonical_content_type:, seed: DEFAULT_SEED)
        p = plan(source_blob_id:, canonical_content_type:, seed:)
        bytes = ffmpeg_render(p)
        raise RenderError, "synthetic video exceeds the byte ceiling" if bytes.bytesize > BYTE_CEILING
        raise RenderError, "synthetic video is empty" if bytes.empty?

        bytes
      end

      # An ADVERSARIAL over-limit body: a genuine, structurally valid H.264 MP4
      # whose authoritative duration deterministically EXCEEDS the 60s brand
      # limit. Kept OUT of the 35-record happy-path corpus — used only by the
      # adversarial suite to prove the fail-closed policy.
      def render_over_limit(seed: DEFAULT_SEED, seconds: MAX_DURATION_SECONDS + 5)
        ffmpeg_render(
          container: "mp4", duration_seconds: seconds, width: 160, height: 120,
          frame_rate: 8, tone_frequency: 300, gop: 8, canonical_content_type: "video/mp4"
        )
      end

      def deterministic_identity(source_blob_id, canonical_content_type, seed)
        Digest::SHA256.hexdigest("#{GENERATOR_VERSION}|#{seed}|#{source_blob_id}|#{canonical_content_type}")
      end

      # ---- ffmpeg (argv array via Open3 — never a shell string) --------------

      def ffmpeg_render(plan)
        Tempfile.create([ "d9j-synth-video", FORMATS.fetch(plan[:canonical_content_type])[:ext] ], binmode: true) do |out|
          out.close
          File.chmod(0o600, out.path)
          args = ffmpeg_args(plan, out.path)
          _stdout, stderr, status = run(args)
          raise RenderError, "ffmpeg exit=#{status&.exitstatus.inspect} #{stderr.to_s[0, 200]}" unless status&.success?

          File.binread(out.path)
        end
      end
      private_class_method :ffmpeg_render

      def ffmpeg_args(plan, out_path)
        duration = plan.fetch(:duration_seconds)
        [
          "ffmpeg", "-y", "-loglevel", "error", "-nostdin",
          "-fflags", "+bitexact", "-flags:v", "+bitexact", "-flags:a", "+bitexact",
          "-f", "lavfi", "-i",
          "testsrc2=size=#{plan.fetch(:width)}x#{plan.fetch(:height)}:rate=#{plan.fetch(:frame_rate)}:duration=#{duration}",
          "-f", "lavfi", "-i",
          "sine=frequency=#{plan.fetch(:tone_frequency)}:duration=#{duration}:sample_rate=44100",
          "-c:v", "libx264", "-preset", "ultrafast", "-x264-params", "bitexact=1",
          "-pix_fmt", "yuv420p", "-g", plan.fetch(:gop).to_s,
          "-c:a", "aac", "-b:a", "64k",
          "-map_metadata", "-1", "-fflags", "+bitexact",
          "-movflags", "+faststart",
          "-f", plan.fetch(:container), out_path
        ]
      end
      private_class_method :ffmpeg_args

      def run(args)
        Open3.popen3(*args) do |stdin, stdout, stderr, wait_thr|
          stdin.close
          out_reader = Thread.new { stdout.read }
          err_reader = Thread.new { stderr.read }
          unless wait_thr.join(RENDER_TIMEOUT)
            Process.kill("KILL", wait_thr.pid)
            wait_thr.join
            out_reader.kill
            err_reader.kill
            raise RenderError, "ffmpeg exceeded #{RENDER_TIMEOUT}s"
          end
          [ out_reader.value, err_reader.value, wait_thr.value ]
        end
      rescue Errno::ENOENT => e
        raise RenderError, "ffmpeg is not available: #{e.message}"
      end
      private_class_method :run
    end
  end
end
