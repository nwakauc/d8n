# frozen_string_literal: true

module Media
  # THE authoritative definition of "a valid, completed, D8N-owned ProfilePhoto
  # display derivative". Every path that treats a display artifact as a finished
  # success — the processing job's ready no-op / finalize / repair decisions and
  # the migration recovery path (Migration::MediaTransfer.valid_accepted_display?)
  # — funnels through here. There is exactly one definition.
  #
  # It proves the EXACT accepted deterministic artifact with a BOUNDED remote
  # read. Metadata alone (attached? + content_type + positive byte_size + a
  # plausible key suffix) is NEVER sufficient: the raw original is intentionally
  # purged once the derivative exists, so this validation is part of recovery
  # correctness.
  #
  # Pure D8N media primitive: validates D8N-owned display media only and carries
  # NO migration / Date9ja semantics. The caller supplies the authoritative
  # expected key + storage service.
  module DisplayDerivative
    # Display derivatives are always JPEG and far smaller than a raw upload;
    # 10MB (ProfilePhoto::MAX_FILE_SIZE) is a safe hard bound for the read.
    BYTE_CEILING = 10.megabytes

    JPEG_MAGIC = "\xFF\xD8\xFF".b.freeze

    class RemoteTooLarge < StandardError; end

    module_function

    # @param photo [ProfilePhoto]
    # @param expected_display_key [String] the authoritative deterministic key
    # @param expected_service [String, Symbol] the authoritative storage service
    # @return [Boolean] true ONLY when the display attachment is the exact
    #   accepted deterministic artifact and its actual remote bytes verify.
    def valid?(photo:, expected_display_key:, expected_service:, image_processor: Media::ImageProcessor)
      return false if expected_display_key.blank? || expected_service.blank?

      attachment = photo.display_image
      return false unless attachment.attached?
      return false unless attachment.record_id == photo.id && attachment.record_type == "ProfilePhoto"

      blob = attachment.blob
      return false unless blob.key == expected_display_key
      return false unless blob.service_name.to_s == expected_service.to_s
      return false unless blob.content_type == Media::ImageProcessor::OUTPUT_CONTENT_TYPE
      return false unless blob.byte_size.to_i.positive?

      service = ActiveStorage::Blob.services.fetch(expected_service.to_sym)
      return false unless service.exist?(expected_display_key)

      bytes = bounded_download(service, expected_display_key)
      return false unless bytes.bytesize == blob.byte_size.to_i
      # Blob.checksum is MD5-base64 of the uploaded display bytes — authoritative.
      return false if blob.checksum.present? && Digest::MD5.base64digest(bytes) != blob.checksum
      return false unless bytes[0, 3] == JPEG_MAGIC

      image_processor.call(bytes) # decodes as the expected image type, or raises
      true
    rescue Media::ImageProcessor::Error, RemoteTooLarge,
           ActiveStorage::FileNotFoundError, Errno::ENOENT, KeyError
      false
    end

    # Streams the remote object, failing closed the instant the running byte
    # count exceeds the ceiling. Never an unbounded service.download(key).
    def bounded_download(service, key)
      buffer = +"".b
      service.download(key) do |chunk|
        buffer << chunk
        raise RemoteTooLarge if buffer.bytesize > BYTE_CEILING
      end
      buffer
    end
  end
end
