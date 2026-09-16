# frozen_string_literal: true

module Media
  # THE authoritative definition of "a valid, completed, D8N-owned ProfileVideo
  # playback + poster derivative" — the video analogue of Media::DisplayDerivative.
  # Every path that treats a safe video derivative as a finished success funnels
  # through here:
  #   - Media::ProcessProfileVideoJob#finalize! validates the CANDIDATE blobs
  #     (`playback_blob_valid?` / `poster_blob_valid?`) BEFORE attaching + marking
  #     ready — deterministic key identity alone is never sufficient (review
  #     Finding 1);
  #   - Media::ProcessProfileVideoJob ready reconciliation and the migration
  #     completion gate (Migration::MediaTransfer.valid_accepted_playback?)
  #     validate the ATTACHED derivatives (`valid?`).
  # There is exactly one definition per derivative kind.
  #
  # It proves the EXACT accepted deterministic artifact with a BOUNDED remote
  # read: exact key + service + content type + positive byte size + remote object
  # exists + remote byte-size match + checksum/body identity match + a real
  # decode (container walk for playback, image decode for poster). Metadata alone
  # is NEVER sufficient — the raw original is purged once the derivatives exist.
  #
  # Pure D8N media primitive: no migration / Date9ja semantics. The caller
  # supplies the authoritative expected keys + storage service.
  module PlaybackDerivative
    PLAYBACK_BYTE_CEILING = Media::VideoPolicy::DEFAULT_MAX_BYTE_SIZE
    POSTER_BYTE_CEILING = 10.megabytes

    JPEG_MAGIC = "\xFF\xD8\xFF".b.freeze
    PLAYBACK_CONTENT_TYPE = "video/mp4"
    POSTER_CONTENT_TYPE = "image/jpeg"

    class RemoteTooLarge < StandardError; end

    module_function

    # ---- ATTACHED-derivative validation (ready reconciliation / migration gate)

    # @return [Boolean] true ONLY when BOTH derivative ATTACHMENTS are the exact
    #   accepted deterministic artifacts and their actual remote bytes verify.
    def valid?(video:, expected_playback_key:, expected_poster_key:, expected_service:,
      image_processor: Media::ImageProcessor, container_validator: Media::VideoContainerValidator)
      return false if expected_playback_key.blank? || expected_poster_key.blank? || expected_service.blank?

      playback_valid?(video:, expected_key: expected_playback_key, expected_service:, container_validator:) &&
        poster_valid?(video:, expected_key: expected_poster_key, expected_service:, image_processor:)
    end

    def playback_valid?(video:, expected_key:, expected_service:, container_validator: Media::VideoContainerValidator)
      attachment = video.playback
      return false unless attachment.attached?
      return false unless attachment.record_id == video.id && attachment.record_type == "ProfileVideo"

      playback_blob_valid?(blob: attachment.blob, expected_key:, expected_service:, container_validator:)
    end

    def poster_valid?(video:, expected_key:, expected_service:, image_processor: Media::ImageProcessor)
      attachment = video.poster
      return false unless attachment.attached?
      return false unless attachment.record_id == video.id && attachment.record_type == "ProfileVideo"

      poster_blob_valid?(blob: attachment.blob, expected_key:, expected_service:, image_processor:)
    end

    # ---- CANDIDATE-blob validation (used before attach/finalize, review Finding 1)
    #
    # Validate an ActiveStorage::Blob DIRECTLY — it need not be attached yet.
    # An existing deterministic-key blob (from a partial prior run or any other
    # writer) may be reused ONLY when this returns true.

    def playback_blob_valid?(blob:, expected_key:, expected_service:,
      container_validator: Media::VideoContainerValidator)
      return false if blob.nil?
      return false unless blob.key == expected_key
      return false unless blob.service_name.to_s == expected_service.to_s
      return false unless blob.content_type == PLAYBACK_CONTENT_TYPE
      return false unless blob.byte_size.to_i.positive?

      service = ActiveStorage::Blob.services.fetch(expected_service.to_sym)
      return false unless service.exist?(expected_key)

      bytes = bounded_download(service, expected_key, PLAYBACK_BYTE_CEILING)
      return false unless bytes.bytesize == blob.byte_size.to_i
      return false unless checksum_matches?(blob, bytes)

      container_validator.call(bytes) # raises unless valid ISO-BMFF + supported codec
      true
    rescue Media::VideoContainerValidator::Error, RemoteTooLarge,
           ActiveStorage::FileNotFoundError, Errno::ENOENT, KeyError
      false
    end

    def poster_blob_valid?(blob:, expected_key:, expected_service:, image_processor: Media::ImageProcessor)
      return false if blob.nil?
      return false unless blob.key == expected_key
      return false unless blob.service_name.to_s == expected_service.to_s
      return false unless blob.content_type == POSTER_CONTENT_TYPE
      return false unless blob.byte_size.to_i.positive?

      service = ActiveStorage::Blob.services.fetch(expected_service.to_sym)
      return false unless service.exist?(expected_key)

      bytes = bounded_download(service, expected_key, POSTER_BYTE_CEILING)
      return false unless bytes.bytesize == blob.byte_size.to_i
      return false unless checksum_matches?(blob, bytes)
      return false unless bytes[0, 3] == JPEG_MAGIC

      image_processor.call(bytes) # decodes as an image, or raises
      true
    rescue Media::ImageProcessor::Error, RemoteTooLarge,
           ActiveStorage::FileNotFoundError, Errno::ENOENT, KeyError
      false
    end

    # A blob's checksum is MD5-base64 of the uploaded bytes and is authoritative
    # when present. Absent checksum => cannot prove body identity => reject.
    def checksum_matches?(blob, bytes)
      return false if blob.checksum.blank?

      Digest::MD5.base64digest(bytes) == blob.checksum
    end

    # Streams the remote object, failing closed the instant the running byte
    # count exceeds the ceiling. Never an unbounded service.download(key).
    def bounded_download(service, key, ceiling)
      buffer = +"".b
      service.download(key) do |chunk|
        buffer << chunk
        raise RemoteTooLarge if buffer.bytesize > ceiling
      end
      buffer
    end
  end
end
