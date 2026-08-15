module Profiles
  # Control-plane/data-plane profile-photo uploads.
  #
  # D8N Rails is the control plane: it authenticates the caller, authorizes the
  # profile, validates the declared media, allocates the object identity, and
  # signs a short-lived upload authorization. The media bytes travel directly
  # between the client and private R2 via that presigned PUT — they never pass
  # through Puma. On completion the client returns the opaque signed id, and D8N
  # verifies the real object before attaching it to the owner's profile.
  #
  # Public/other-user delivery, safe re-encoding, EXIF removal, and moderation
  # remain gated (see docs/operations/private-media-storage.md and ADR 0011).
  # Uploaded photos are owner-only, pending review, and hidden until that
  # pipeline ships.
  class PhotoUpload
    MAX_FILE_SIZE = ProfilePhoto::MAX_FILE_SIZE
    ALLOWED_CONTENT_TYPES = ProfilePhoto::ALLOWED_CONTENT_TYPES
    UPLOAD_URL_EXPIRES_IN = 10.minutes
    RETRIEVAL_URL_EXPIRES_IN = 5.minutes

    Error = Class.new(StandardError)
    ProfileRequired = Class.new(Error)
    InvalidContentType = Class.new(Error)
    InvalidSize = Class.new(Error)
    InvalidUpload = Class.new(Error)
    AlreadyAttached = Class.new(Error)
    MissingObject = Class.new(Error)
    InvalidObject = Class.new(Error)

    # Control plane: allocate a D8N-controlled object key and return a short-lived
    # presigned PUT the client uses to upload bytes straight to private R2.
    def self.create_intent(user:, brand:, filename:, byte_size:, checksum:, content_type:)
      require_profile!(user:, brand:)

      content_type = content_type.to_s
      raise InvalidContentType unless ALLOWED_CONTENT_TYPES.include?(content_type)

      byte_size = Integer(byte_size, exception: false)
      raise InvalidSize unless byte_size&.positive? && byte_size <= MAX_FILE_SIZE

      checksum = checksum.to_s
      raise InvalidUpload if checksum.blank?

      blob = ActiveStorage::Blob.create_before_direct_upload!(
        filename: filename.to_s.presence || "photo",
        byte_size:,
        checksum:,
        content_type:,
        service_name: ActiveStorage::Blob.service.name
      )

      {
        signed_id: blob.signed_id,
        url: blob.service_url_for_direct_upload(expires_in: UPLOAD_URL_EXPIRES_IN),
        headers: blob.service_headers_for_direct_upload,
        expires_in: UPLOAD_URL_EXPIRES_IN.to_i,
        byte_size_limit: MAX_FILE_SIZE,
        allowed_content_types: ALLOWED_CONTENT_TYPES
      }
    end

    # Data plane completion: verify the real object exists and is a supported
    # image, then attach it to the authenticated owner's profile.
    def self.attach!(user:, brand:, signed_id:, position: nil)
      profile = require_profile!(user:, brand:)

      blob = ActiveStorage::Blob.find_signed(signed_id.to_s)
      raise InvalidUpload if blob.nil?
      raise AlreadyAttached if blob.attachments.exists?

      verify_uploaded_object!(blob)

      photo = ProfilePhoto.new(
        profile:,
        user:,
        brand:,
        position: position.presence || next_position(profile)
      )
      photo.image.attach(blob)
      photo.save!
      photo
    end

    # Trust the object, not the client's declared metadata: confirm the upload
    # actually landed, sniff the real file signature, bound the real size, and
    # reconcile the blob record to that verified truth before attachment.
    def self.verify_uploaded_object!(blob)
      service = blob.service
      raise MissingObject unless service.exist?(blob.key)

      detected_type = detect_image_type(service.download_chunk(blob.key, 0...16))
      raise InvalidObject if detected_type.nil?

      actual_size = object_byte_size(service, blob.key)
      raise InvalidSize if actual_size.nil? || actual_size <= 0 || actual_size > MAX_FILE_SIZE

      blob.update!(content_type: detected_type, byte_size: actual_size)
    end

    def self.require_profile!(user:, brand:)
      Profile.kept.find_by(user:, brand:) || raise(ProfileRequired)
    end

    def self.next_position(profile)
      profile.profile_photos.kept.maximum(:position).to_i + 1
    end

    # Magic-byte detection for the supported image types. The client-declared
    # MIME is only a hint; this is the authority.
    def self.detect_image_type(head)
      bytes = head.to_s.b
      return "image/jpeg" if bytes[0, 3] == "\xFF\xD8\xFF".b
      return "image/png" if bytes[0, 8] == "\x89PNG\r\n\x1A\n".b
      return "image/webp" if bytes[0, 4] == "RIFF".b && bytes[8, 4] == "WEBP".b

      nil
    end

    def self.object_byte_size(service, key)
      if service.respond_to?(:bucket)
        # S3-compatible services (R2 in production) expose the bucket. The object
        # is confirmed present by the caller's exist? check first, so this HEAD is
        # cheap and does not stream the bytes through the app.
        service.bucket.object(key).content_length
      else
        # Portable fallback (Disk in dev/test): read at most one byte past the
        # limit so an oversized object is rejected without a full download.
        service.download_chunk(key, 0...(MAX_FILE_SIZE + 1)).bytesize
      end
    rescue Errno::ENOENT
      nil
    end

    private_class_method :require_profile!, :verify_uploaded_object!, :object_byte_size
  end
end
