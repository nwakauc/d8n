# frozen_string_literal: true

require "test_helper"
require "vips"

module Migration
  class MediaTransferTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper
    Ck = MediaTransfer::CanonicalKey

    # Streams pre-verified bytes for a single key. Mirrors the SourceReader
    # surface used by Migration::MediaTransfer.
    class FakeReader
      def initialize(bytes:, key: "legacy-key", missing: false)
        @bytes = bytes.b
        @key = key
        @missing = missing
      end

      def head(key)
        return nil if @missing || key != @key

        { byte_size: @bytes.bytesize }
      end

      def download(key, io:, byte_ceiling:, chunk_size: 5.megabytes)
        raise Date9ja::Storage::SourceReader::ObjectUnavailable if @missing || key != @key

        written = 0
        @bytes.bytes.each_slice(chunk_size) do |slice|
          chunk = slice.pack("C*")
          written += chunk.bytesize
          raise Date9ja::Storage::SourceReader::ByteCeilingExceeded if written > byte_ceiling

          io.write(chunk)
        end
        io.flush
        written
      end
    end

    def valid_jpeg(seed: 1)
      Vips::Image.black(80, 60).add([ 40 + seed ]).cast("uchar").write_to_buffer(".jpg").b
    end

    def dest_service = ActiveStorage::Blob.service.name.to_s

    setup { @sid = SecureRandom.hex(8) }

    def preflight_ref(bytes, source_blob_id: @sid)
      ref, = Migration::MediaObjectRef.preflight!(
        source_system: "date9ja", source_blob_id:,
        checksum: Digest::MD5.base64digest(bytes), byte_size: bytes.bytesize, content_type: "image/jpeg",
        importer_version: "date9ja-photo-preflight-v1"
      )
      ref
    end

    def identity(source_blob_id: @sid, source_attachment_id: "att-#{@sid}")
      Ck::Identity.new(
        source_system: "date9ja", source_blob_id:, source_attachment_id:,
        destination_purpose: "profile_photo_original", destination_brand: "date9ja",
        canonical_content_type: nil
      )
    end

    def run_transfer(bytes, reader: nil, source_blob_id: @sid)
      reader ||= FakeReader.new(bytes:)
      Migration::MediaTransfer.call(
        object_ref: preflight_ref(bytes, source_blob_id:), source_reader: reader, source_key: "legacy-key",
        identity: identity(source_blob_id:), dest_service_name: dest_service
      )
    end

    # --- case 1 ---------------------------------------------------------------

    test "case 1: clean transfer uploads and returns a verified object-backed blob" do
      bytes = valid_jpeg
      result = run_transfer(bytes)

      assert result.ok?, result.inspect
      assert_equal "image/jpeg", result.canonical_content_type
      blob = result.blob
      assert blob.persisted?
      assert blob.service.exist?(blob.key)
      assert_equal Digest::MD5.base64digest(bytes), blob.checksum
      assert_equal result.final_key, blob.key
      assert blob.key.start_with?("migrations/media/v3/date9ja/profile_photo_original/")
    end

    # --- case 2 ---------------------------------------------------------------

    test "case 2: a byte-identical existing blob+object is safely reused" do
      bytes = valid_jpeg
      first = run_transfer(bytes)
      second = run_transfer(bytes)

      assert second.ok?
      assert_equal first.blob.id, second.blob.id
    end

    test "case 2: a tampered remote object (row metadata matches, bytes differ) is a collision" do
      bytes = valid_jpeg
      result = run_transfer(bytes)
      blob = result.blob
      # Overwrite the object with different bytes but keep the row identity.
      blob.service.upload(blob.key, StringIO.new(valid_jpeg(seed: 99)))

      again = run_transfer(bytes)
      assert_equal :binding_conflict, again.disposition
      assert_equal "destination_collision", again.reason
    end

    # --- case 3 ---------------------------------------------------------------

    test "case 3: an orphan blob row (object missing) is recovered by re-upload" do
      bytes = valid_jpeg
      result = run_transfer(bytes)
      blob = result.blob
      blob.service.delete(blob.key)
      refute blob.service.exist?(blob.key)

      recovered = run_transfer(bytes)
      assert recovered.ok?
      assert_equal blob.id, recovered.blob.id
      assert recovered.blob.service.exist?(blob.key)
    end

    # --- case 4 ---------------------------------------------------------------

    test "case 4: a remote object with no blob row is quarantined, never adopted" do
      bytes = valid_jpeg
      key = Ck.final_key(identity.with(canonical_content_type: "image/jpeg"))
      ActiveStorage::Blob.service.upload(key, StringIO.new(bytes))

      result = run_transfer(bytes)
      assert_equal :binding_conflict, result.disposition
      assert_equal "remote_orphan", result.reason
      assert_nil ActiveStorage::Blob.find_by(key:), "no blob row may be manufactured"
    end

    # --- verification failures ----------------------------------------------

    test "size mismatch -> source_changed" do
      bytes = valid_jpeg
      ref = preflight_ref(bytes, source_blob_id: "blob-x")
      ref.update_columns(byte_size: bytes.bytesize + 10, source_fingerprint: "x" * 32)
      result = Migration::MediaTransfer.call(
        object_ref: ref, source_reader: FakeReader.new(bytes:), source_key: "legacy-key",
        identity: identity(source_blob_id: "blob-x"), dest_service_name: dest_service
      )
      assert_equal :source_changed, result.disposition
    end

    test "checksum mismatch -> source_changed" do
      bytes = valid_jpeg
      ref = preflight_ref(bytes, source_blob_id: "blob-c")
      ref.update_columns(checksum: Digest::MD5.base64digest("other"), source_fingerprint: "y" * 32)
      result = Migration::MediaTransfer.call(
        object_ref: ref, source_reader: FakeReader.new(bytes:), source_key: "legacy-key",
        identity: identity(source_blob_id: "blob-c"), dest_service_name: dest_service
      )
      assert_equal :source_changed, result.disposition
    end

    test "non-image bytes -> validation_failed(not_an_image)" do
      bytes = "this is definitely not an image".b
      result = run_transfer(bytes, source_blob_id: "blob-n")
      assert_equal :validation_failed, result.disposition
      assert_equal "not_an_image", result.reason
    end

    test "missing source object -> source_unavailable" do
      bytes = valid_jpeg
      result = run_transfer(bytes, reader: FakeReader.new(bytes:, missing: true))
      assert_equal :source_unavailable, result.disposition
    end

    test "byte ceiling -> validation_failed(oversize)" do
      bytes = valid_jpeg
      ref = preflight_ref(bytes, source_blob_id: "blob-big")
      ref.update_columns(byte_size: 9.megabytes, source_fingerprint: "z" * 32)
      huge = "\xFF\xD8\xFF".b + ("x" * 9.megabytes)
      result = Migration::MediaTransfer.call(
        object_ref: ref, source_reader: FakeReader.new(bytes: huge), source_key: "legacy-key",
        identity: identity(source_blob_id: "blob-big"), dest_service_name: dest_service
      )
      assert_equal :validation_failed, result.disposition
      assert_equal "oversize", result.reason
    end

    test "content-type drift (detected != preflighted) -> source_changed" do
      png = Vips::Image.black(60, 40).write_to_buffer(".png").b
      ref, = Migration::MediaObjectRef.preflight!(
        source_system: "date9ja", source_blob_id: "blob-ct",
        checksum: Digest::MD5.base64digest(png), byte_size: png.bytesize, content_type: "image/jpeg",
        importer_version: "v"
      )
      result = Migration::MediaTransfer.call(
        object_ref: ref, source_reader: FakeReader.new(bytes: png), source_key: "legacy-key",
        identity: identity(source_blob_id: "blob-ct"), dest_service_name: dest_service
      )
      assert_equal :source_changed, result.disposition
      assert_equal "content_type_drift", result.reason
    end

    # --- Finding 2: no remote I/O under a DB lock -----------------------------

    test "service.exist? / download / libvips fail closed while a migration lock is held" do
      bytes = valid_jpeg
      result = run_transfer(bytes)
      blob = result.blob
      svc = ActiveStorage::Blob.service

      Migration::MediaTransfer::LockGuard.hold do
        assert_raises(Migration::MediaTransfer::RemoteIOUnderLock) { Migration::MediaTransfer.service_exist?(svc, blob.key) }
        assert_raises(Migration::MediaTransfer::RemoteIOUnderLock) { Migration::MediaTransfer.bounded_download(svc, blob.key, 8.megabytes) }
      end
    end

    test "AdoptOrUpload holds no lock across its remote work (case 1)" do
      # If any remote op ran under LockGuard, call would raise RemoteIOUnderLock.
      assert run_transfer(valid_jpeg).ok?
    end

    test "case 2/3: a blob-row identity change between external work and recheck fails closed" do
      bytes = valid_jpeg
      blob = run_transfer(bytes).blob
      # Simulate a concurrent writer swapping the row identity.
      blob.update_columns(checksum: Digest::MD5.base64digest("other"))

      again = run_transfer(bytes)
      assert_equal :binding_conflict, again.disposition
      assert_equal "destination_collision", again.reason
    end

    test "repeated identical workers converge on one blob (idempotent case 2)" do
      bytes = valid_jpeg
      ids = 3.times.map { run_transfer(bytes).blob.id }
      assert_equal 1, ids.uniq.size
    end

    # --- Finding 4: display derivative validation --------------------------

    def ready_photo_with_display(bytes: nil)
      bytes ||= valid_jpeg
      brand = Brand.create!(slug: "hookus", name: "HookUs")
      user = User.create!
      m = BrandMembership.create!(brand:, user:)
      profile = Profile.create!(brand:, user:, brand_membership: m, display_name: "A",
        birthdate: 25.years.ago.to_date, gender: "woman")
      okey = "migrations/media/v3/date9ja/profile_photo_original/#{SecureRandom.uuid}/original.jpg"
      raw = ActiveStorage::Blob.create_and_upload!(io: StringIO.new(bytes), key: okey, filename: "original.jpg",
        content_type: "image/jpeg", service_name: dest_service)
      photo = ProfilePhoto.new(brand:, user:, profile:)
      photo.image.attach(raw)
      photo.save!
      perform_enqueued_jobs { Media::ProcessProfilePhotoJob.perform_now(photo.id) }
      [ photo.reload, Media::ObjectKey.profile_photo_display(okey) ]
    end

    test "valid_accepted_display?: true only for the exact deterministic artifact" do
      photo, dkey = ready_photo_with_display
      assert Migration::MediaTransfer.valid_accepted_display?(
        photo:, expected_display_key: dkey, expected_service: dest_service
      )
    end

    test "valid_accepted_display?: false for a wrong exact key with the right prefix" do
      photo, dkey = ready_photo_with_display
      wrong = dkey.sub(%r{/[^/]+/display\.jpg\z}, "/#{SecureRandom.uuid}/display.jpg")
      refute Migration::MediaTransfer.valid_accepted_display?(
        photo:, expected_display_key: wrong, expected_service: dest_service
      )
    end

    test "valid_accepted_display?: false for the wrong service" do
      photo, dkey = ready_photo_with_display
      refute Migration::MediaTransfer.valid_accepted_display?(
        photo:, expected_display_key: dkey, expected_service: "brand_test"
      )
    end

    test "valid_accepted_display?: false when the remote object is missing" do
      photo, dkey = ready_photo_with_display
      photo.display_image.blob.service.delete(dkey)
      refute Migration::MediaTransfer.valid_accepted_display?(
        photo:, expected_display_key: dkey, expected_service: dest_service
      )
    end

    test "valid_accepted_display?: false when the remote bytes are tampered" do
      photo, dkey = ready_photo_with_display
      photo.display_image.blob.service.upload(dkey, StringIO.new("not an image"))
      refute Migration::MediaTransfer.valid_accepted_display?(
        photo:, expected_display_key: dkey, expected_service: dest_service
      )
    end

    test "valid_accepted_display?: false when no display is attached" do
      photo, dkey = ready_photo_with_display
      photo.display_image.detach
      refute Migration::MediaTransfer.valid_accepted_display?(
        photo: photo.reload, expected_display_key: dkey, expected_service: dest_service
      )
    end

    test "a failed preflight row is never transferred" do
      ref, = Migration::MediaObjectRef.preflight!(
        source_system: "date9ja", source_blob_id: "blob-f", checksum: nil, byte_size: nil,
        content_type: nil, importer_version: "v", preflight_state: :failed, failure_code: "bad"
      )
      result = Migration::MediaTransfer.call(
        object_ref: ref, source_reader: FakeReader.new(bytes: valid_jpeg), source_key: "legacy-key",
        identity: identity(source_blob_id: "blob-f"), dest_service_name: dest_service
      )
      assert_equal :source_unavailable, result.disposition
      assert_equal "preflight_failed", result.reason
    end
  end
end
