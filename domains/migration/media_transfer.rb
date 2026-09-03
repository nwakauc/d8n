# frozen_string_literal: true

module Migration
  # Shared, source-system-agnostic byte transfer for one source storage object
  # (ADR 0028). Given a preflighted Migration::MediaObjectRef, an injected
  # source reader, and the source object key, it:
  #
  #   1. streams the source bytes to a private 0600 temp file under a hard ceiling
  #   2. verifies size, MD5-base64, magic bytes, and libvips decode safety (§6);
  #      the detected media type MUST equal the preflighted canonical_content_type
  #      (a divergence is source_changed, never a silent re-key)
  #   3. derives the deterministic destination key from the complete canonical
  #      migration identity (Migration::MediaTransfer::CanonicalKey, §7)
  #   4. adopt-or-uploads the destination ActiveStorage::Blob, re-verifying the
  #      actual remote object on every reuse path with BOUNDED streaming, and
  #      never performing storage/network/libvips work under a DB lock (§7b, §7c)
  #
  # It knows nothing about legacy schemas, brands, ProfilePhoto, ReferenceMap, or
  # ordering. All of that stays in Date9ja::Import::PhotoTransfer.
  module MediaTransfer
    # Lower of Date9ja Photo::MAX_FILE_SIZE (8MB) and D8N ProfilePhoto (10MB).
    BYTE_CEILING = 8.megabytes
    CHUNK_SIZE = 5.megabytes
    ALLOWED_CONTENT_TYPES = %w[image/jpeg image/png image/webp].freeze

    Result = Data.define(:disposition, :reason, :blob, :final_key, :canonical_content_type) do
      def ok? = disposition == :ok

      def self.ok(blob:, final_key:, canonical_content_type:)
        new(disposition: :ok, reason: nil, blob:, final_key:, canonical_content_type:)
      end

      def self.failed(disposition, reason)
        new(disposition:, reason:, blob: nil, final_key: nil, canonical_content_type: nil)
      end
    end

    class GlobalBlocker < StandardError; end
    # Raised if a storage / network / libvips operation is attempted while a DB
    # row lock or migration transaction is held (ADR 0028 §7c). Defence in depth.
    class RemoteIOUnderLock < StandardError; end
    class DestinationTooLarge < StandardError; end

    # Tracks whether a migration DB lock / short finalization transaction is
    # currently held on THIS thread, so remote I/O can fail closed rather than
    # run under it. Not `connection.transaction_open?` — the test harness wraps
    # every test in a transaction.
    module LockGuard
      KEY = :migration_media_transfer_lock_depth

      module_function

      def held? = (Thread.current[KEY] || 0).positive?

      def hold
        Thread.current[KEY] = (Thread.current[KEY] || 0) + 1
        yield
      ensure
        Thread.current[KEY] = (Thread.current[KEY] || 1) - 1
      end

      def assert_free!(operation)
        raise RemoteIOUnderLock, operation if held?
      end
    end

    module_function

    def call(object_ref:, source_reader:, source_key:, identity:, dest_service_name:,
      image_processor: Media::ImageProcessor)
      return Result.failed(:source_unavailable, "preflight_failed") unless transferable?(object_ref)

      expected = expected_identity(object_ref)
      tempfile = Tempfile.new("migration-media-transfer", binmode: true)
      File.chmod(0o600, tempfile.path)

      begin
        streamed = stream_source!(source_reader, source_key, tempfile)
        return streamed if streamed.is_a?(Result)

        verified = verify_bytes!(tempfile, expected, image_processor)
        return verified if verified.is_a?(Result)

        content_type = verified # detected == expected canonical content type
        full_identity = identity.with(canonical_content_type: content_type)
        final_key = CanonicalKey.final_key(full_identity)

        blob = AdoptOrUpload.call(
          key: final_key,
          io: tempfile,
          expected: expected.merge(content_type:, dest_service: dest_service_name.to_s),
          image_processor:
        )
        return blob if blob.is_a?(Result)

        Result.ok(blob:, final_key:, canonical_content_type: content_type)
      ensure
        tempfile.close
        tempfile.unlink
      end
    end

    def transferable?(object_ref)
      object_ref.preflight_preflighted? && object_ref.byte_size.to_i.positive? &&
        object_ref.checksum.present? && object_ref.content_type.present?
    end

    def expected_identity(object_ref)
      {
        md5: object_ref.checksum.to_s,
        byte_size: object_ref.byte_size.to_i,
        content_type: object_ref.content_type.to_s
      }
    end

    def stream_source!(source_reader, source_key, tempfile)
      head = source_reader.head(source_key)
      return Result.failed(:source_unavailable, "source_object_missing") if head.nil?

      source_reader.download(source_key, io: tempfile, byte_ceiling: BYTE_CEILING, chunk_size: CHUNK_SIZE)
      tempfile.flush
      tempfile.rewind
      nil
    rescue Date9ja::Storage::SourceReader::ByteCeilingExceeded
      Result.failed(:validation_failed, "oversize")
    rescue Date9ja::Storage::SourceReader::RedirectRefused,
           Date9ja::Storage::SourceReader::EndpointRejected,
           Date9ja::Storage::SourceReader::InvalidKey
      Result.failed(:source_unavailable, "source_transport_refused")
    rescue Date9ja::Storage::SourceReader::ObjectUnavailable
      Result.failed(:source_unavailable, "source_object_unavailable")
    end

    # Returns the detected canonical content type (String) on success, or a
    # failure Result. Exact order (MEDIA-TRANSFER.md §6).
    def verify_bytes!(tempfile, expected, image_processor)
      tempfile.rewind
      actual_size = File.size(tempfile.path)
      return Result.failed(:validation_failed, "oversize") if actual_size > BYTE_CEILING
      return Result.failed(:source_changed, "source_size_mismatch") unless actual_size == expected[:byte_size]

      bytes = File.binread(tempfile.path)
      return Result.failed(:source_changed, "source_checksum_mismatch") unless Digest::MD5.base64digest(bytes) == expected[:md5]

      detected = Profiles::PhotoUpload.detect_image_type(bytes[0, 16])
      return Result.failed(:validation_failed, "not_an_image") if detected.nil?
      return Result.failed(:validation_failed, "unsupported_content_type") unless ALLOWED_CONTENT_TYPES.include?(detected)

      # Security: the detected type must EQUAL the preflighted canonical type,
      # not merely be allowlisted. A divergence is source-content drift.
      return Result.failed(:source_changed, "content_type_drift") unless detected == expected[:content_type]

      begin
        LockGuard.assert_free!("image_processor.call")
        image_processor.call(bytes)
      rescue Media::ImageProcessor::Error
        return Result.failed(:validation_failed, "malformed_image")
      end

      detected
    end

    # Bounded remote read: streams the object and fails closed the moment the
    # running byte count exceeds `ceiling`. Used for every destination re-verify.
    def bounded_download(service, key, ceiling)
      LockGuard.assert_free!("service.download")
      buffer = +"".b
      service.download(key) do |chunk|
        buffer << chunk
        raise DestinationTooLarge if buffer.bytesize > ceiling
      end
      buffer
    end

    def service_exist?(service, key)
      LockGuard.assert_free!("service.exist?")
      service.exist?(key)
    end

    # Validation of a D8N-owned display derivative on the migration recovery path
    # (MEDIA-TRANSFER.md §16b / review Finding 4). Delegates to the single shared
    # authoritative contract — Media::DisplayDerivative.valid? — which proves the
    # EXACT accepted deterministic artifact with a bounded remote read and full
    # integrity verification. Metadata alone is never sufficient.
    #
    # The migration LockGuard assertion stays here as defence in depth: the
    # shared primitive does bounded remote I/O and must never run while a
    # migration DB lock / short finalization transaction is held.
    #
    # @return [true, false]
    def valid_accepted_display?(photo:, expected_display_key:, expected_service:,
      image_processor: Media::ImageProcessor)
      LockGuard.assert_free!("valid_accepted_display?")
      Media::DisplayDerivative.valid?(
        photo:, expected_display_key:, expected_service:, image_processor:
      )
    end
  end
end
