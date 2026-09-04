# frozen_string_literal: true

module Migration
  # Shared, source-system-agnostic byte transfer for one source storage object
  # (ADR 0028, generalized across media kinds by ADR 0029). Given a preflighted
  # Migration::MediaObjectRef, an injected source reader, the source object key,
  # and a Migration::MediaTransfer::MediaKind strategy, it:
  #
  #   1. streams the source bytes to a private 0600 temp file under the kind's
  #      hard byte ceiling
  #   2. verifies size, MD5-base64, kind-specific magic/container type, and the
  #      kind's structural validation (§6); the detected media type MUST equal
  #      the preflighted canonical_content_type (a divergence is source_changed,
  #      never a silent re-key)
  #   3. runs the optional Phase-A media gate (video duration-policy check) — a
  #      rejection stops here, BEFORE any destination adoption
  #   4. derives the deterministic destination key from the complete canonical
  #      migration identity (Migration::MediaTransfer::CanonicalKey, §7)
  #   5. adopt-or-uploads the destination ActiveStorage::Blob, re-verifying the
  #      actual remote object on every reuse path with BOUNDED streaming, and
  #      never performing storage/network/libvips/ffprobe work under a DB lock
  #
  # It knows nothing about legacy schemas, brands, ProfilePhoto/ProfileVideo,
  # ReferenceMap, ordering, or which brand a duration limit belongs to. All of
  # that stays in Date9ja::Import::{PhotoTransfer,VideoTransfer}.
  #
  # `media_kind` defaults to MediaKind::Image, whose behaviour is byte-for-byte
  # the pre-0029 Profile Photo path.
  module MediaTransfer
    # Retained for existing image callers (Date9ja::Import::PhotoTransfer reads
    # this constant). New code asks the media kind: `media_kind.content_types`.
    ALLOWED_CONTENT_TYPES = MediaKind::Image::CONTENT_TYPES
    # Retained image byte ceiling constant; the transfer uses
    # `media_kind.byte_ceiling`.
    BYTE_CEILING = MediaKind::Image::BYTE_CEILING
    CHUNK_SIZE = 5.megabytes

    Result = Data.define(:disposition, :reason, :blob, :final_key, :canonical_content_type, :media_facts) do
      def ok? = disposition == :ok

      def self.ok(blob:, final_key:, canonical_content_type:, media_facts: nil)
        new(disposition: :ok, reason: nil, blob:, final_key:, canonical_content_type:,
          media_facts: media_facts || MediaKind::Facts.empty)
      end

      def self.failed(disposition, reason, media_facts: nil)
        new(disposition:, reason:, blob: nil, final_key: nil, canonical_content_type: nil, media_facts:)
      end
    end

    class GlobalBlocker < StandardError; end
    # Raised if a storage / network / libvips / ffprobe operation is attempted
    # while a DB row lock or migration transaction is held (ADR 0028 §7c).
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
      media_kind: MediaKind::DEFAULT, media_gate: nil, image_processor: Media::ImageProcessor)
      return Result.failed(:source_unavailable, "preflight_failed") unless transferable?(object_ref)

      expected = expected_identity(object_ref)
      tempfile = Tempfile.new("migration-media-transfer", binmode: true)
      File.chmod(0o600, tempfile.path)

      begin
        streamed = stream_source!(source_reader, source_key, tempfile, media_kind.byte_ceiling)
        return streamed if streamed.is_a?(Result)

        verified = verify_bytes!(tempfile, expected, media_kind, image_processor)
        return verified if verified.is_a?(Result)

        content_type, facts = verified

        if media_gate
          gate = media_gate.call(facts)
          return gate if gate.is_a?(Result)
        end

        full_identity = identity.with(canonical_content_type: content_type)
        final_key = CanonicalKey.final_key(full_identity)

        blob = AdoptOrUpload.call(
          key: final_key,
          io: tempfile,
          expected: expected.merge(content_type:, dest_service: dest_service_name.to_s),
          media_kind:,
          image_processor:
        )
        return blob if blob.is_a?(Result)

        Result.ok(blob:, final_key:, canonical_content_type: content_type, media_facts: facts)
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

    def stream_source!(source_reader, source_key, tempfile, byte_ceiling)
      head = source_reader.head(source_key)
      return Result.failed(:source_unavailable, "source_object_missing") if head.nil?

      source_reader.download(source_key, io: tempfile, byte_ceiling:, chunk_size: CHUNK_SIZE)
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

    # Returns [detected_canonical_content_type (String), MediaKind::Facts] on
    # success, or a failure Result. Exact order (MEDIA-TRANSFER.md §6 / ADR 0029).
    def verify_bytes!(tempfile, expected, media_kind, image_processor)
      tempfile.rewind
      ceiling = media_kind.byte_ceiling
      actual_size = File.size(tempfile.path)
      return Result.failed(:validation_failed, "oversize") if actual_size > ceiling
      return Result.failed(:source_changed, "source_size_mismatch") unless actual_size == expected[:byte_size]

      bytes = File.binread(tempfile.path)
      return Result.failed(:source_changed, "source_checksum_mismatch") unless Digest::MD5.base64digest(bytes) == expected[:md5]

      detected = media_kind.detect_type(bytes)
      return Result.failed(:validation_failed, media_kind.not_recognized_reason) if detected.nil?
      return Result.failed(:validation_failed, "unsupported_content_type") unless media_kind.content_types.include?(detected)

      # Security: the detected type must EQUAL the preflighted canonical type,
      # not merely be allowlisted. A divergence is source-content drift.
      return Result.failed(:source_changed, "content_type_drift") unless detected == expected[:content_type]

      begin
        LockGuard.assert_free!("media_kind.structural_verify!")
        facts = media_kind.structural_verify!(bytes, image_processor:)
      rescue MediaKind::StructuralError => e
        return Result.failed(e.disposition, e.reason)
      end

      [ detected, facts ]
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
    # @return [true, false]
    def valid_accepted_display?(photo:, expected_display_key:, expected_service:,
      image_processor: Media::ImageProcessor)
      LockGuard.assert_free!("valid_accepted_display?")
      Media::DisplayDerivative.valid?(
        photo:, expected_display_key:, expected_service:, image_processor:
      )
    end

    # Video analogue (ADR 0029 Pass 2B). Proves the EXACT accepted deterministic
    # playback + poster derivative pair for a migrated ProfileVideo with bounded
    # remote reads. Delegates to the single shared authoritative contract —
    # Media::PlaybackDerivative.valid? — and keeps the migration LockGuard
    # assertion as defence in depth: bounded remote I/O must never run while a
    # migration DB lock / short finalization transaction is held.
    #
    # @return [true, false]
    def valid_accepted_playback?(video:, expected_playback_key:, expected_poster_key:, expected_service:)
      LockGuard.assert_free!("valid_accepted_playback?")
      Media::PlaybackDerivative.valid?(
        video:, expected_playback_key:, expected_poster_key:, expected_service:
      )
    end
  end
end
