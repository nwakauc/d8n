ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "open3"
require "tempfile"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    def issue_mfa_verified_admin_session!(user:, brand:, admin_user:)
      credential = admin_user.admin_mfa_credentials.kept.active.first_or_create!(
        secret: Admin::Mfa::Totp.generate_secret,
        confirmed_at: Time.current,
        recovery_code_digests: []
      )
      raw_token, session = Session.issue!(brand:, user:)
      session.update!(admin_mfa_credential: credential, admin_mfa_verified_at: Time.current)
      raw_token
    end

    # Temporarily replace a singleton (class) method with `replacement` for the
    # duration of the block, then restore the original. A dependency-free stand-in
    # for mock libraries, used to swap outbound HTTP transports in gateway specs.
    def stub_method(owner, name, replacement)
      original = owner.method(name)
      owner.define_singleton_method(name, replacement)
      yield
    ensure
      owner.define_singleton_method(name, original)
    end

    # Builds a minimal-but-real ISO-BMFF (MP4) byte string: ftyp + moov (mvhd +
    # one video trak with a stsd sample entry) + mdat. Used across chat-media
    # tests instead of a fixture binary so the exact bytes under test are
    # visible in the test itself. `codec` is the 4-byte sample entry format
    # (e.g. "avc1", "hvc1", "vp09"); `brand` is the ftyp major_brand.
    def build_test_mp4_bytes(codec: "avc1", brand: "isom", duration_units: 5000, timescale: 1000)
      box = ->(type, body) { [ body.bytesize + 8 ].pack("N") + type + body }

      ftyp = box.call("ftyp", brand + [ 0 ].pack("N") + "isomiso2mp41")
      mvhd = box.call(
        "mvhd",
        [ 0 ].pack("N") + ("\x00" * 8) + [ timescale ].pack("N") + [ duration_units ].pack("N") + ("\x00" * 60)
      )
      hdlr = box.call("hdlr", [ 0 ].pack("N") + [ 0 ].pack("N") + "vide" + ("\x00" * 12))
      sample_entry = [ 100 ].pack("N") + codec + ("\x00" * 92)
      stsd = box.call("stsd", [ 0 ].pack("N") + [ 1 ].pack("N") + sample_entry)
      stbl = box.call("stbl", stsd)
      minf = box.call("minf", stbl)
      mdia = box.call("mdia", hdlr + minf)
      trak = box.call("trak", mdia)
      moov = box.call("moov", mvhd + trak)
      mdat = box.call("mdat", "x" * 32)

      (ftyp + moov + mdat).b
    end

    def build_test_jpeg_bytes(width: 60, height: 40)
      Vips::Image.black(width, height).add([ 120 ]).cast("uchar").write_to_buffer(".jpg")
    end

    # Builds a REAL, decodable synthetic video via ffmpeg (a generated test
    # pattern + tone, not a fixture binary) for tests that exercise actual
    # processing (Media::VideoProcessor transcode/poster generation), where
    # `build_test_mp4_bytes`'s hand-built box structure (real headers, fake
    # sample data) is not decodable and would fail every real ffmpeg/ffprobe
    # call. Requires `ffmpeg` on PATH — the same runtime dependency
    # Media::VideoProcessor itself requires in every environment (see Dockerfile).
    def build_real_test_video_bytes(video_codec: "libx264", container: "mp4", duration: 1, extra_args: [])
      Tempfile.create([ "d8n-test-video", ".#{container}" ]) do |file|
        file.close
        args = [
          "ffmpeg", "-y",
          "-f", "lavfi", "-i", "testsrc=duration=#{duration}:size=64x64:rate=5",
          "-f", "lavfi", "-i", "sine=frequency=1000:duration=#{duration}",
          "-c:v", video_codec, "-c:a", "aac", *extra_args,
          file.path
        ]
        _stdout, stderr, status = Open3.capture3(*args)
        raise "ffmpeg test fixture build failed: #{stderr}" unless status.success?

        File.binread(file.path)
      end
    end

    def build_test_h264_mp4_bytes(duration: 1)
      build_real_test_video_bytes(video_codec: "libx264", container: "mp4", duration:)
    end

    def build_test_hevc_mp4_bytes(duration: 1)
      build_real_test_video_bytes(video_codec: "libx265", container: "mp4", duration:, extra_args: %w[ -tag:v hvc1 ])
    end

    def build_test_h264_mov_bytes(duration: 1)
      build_real_test_video_bytes(video_codec: "libx264", container: "mov", duration:)
    end

    # Present Profiles::FieldCatalog as if it also defined `extra_fields`, only
    # for the duration of the block, by swapping its authoritative constants.
    # Used to prove FieldPolicy / the serializers fail closed on a
    # sensitive-identity or pending-storage field a brand should never be able
    # to enable — before any such field is a real catalogue definition.
    def with_field_catalog_extra(*extra_fields)
      catalog = Profiles::FieldCatalog
      original_all = catalog::ALL
      original_by_key = catalog::BY_KEY
      swap = lambda do |name, value|
        catalog.send(:remove_const, name)
        catalog.const_set(name, value)
      end
      swap.call(:ALL, (original_all + extra_fields).freeze)
      swap.call(:BY_KEY, original_by_key.merge(extra_fields.index_by(&:key)).freeze)
      yield
    ensure
      swap.call(:ALL, original_all)
      swap.call(:BY_KEY, original_by_key)
    end
  end
end
