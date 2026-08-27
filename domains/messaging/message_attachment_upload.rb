module Messaging
  # Control-plane/data-plane uploads for D8N Chat Media (image/video message
  # attachments), mirroring Profiles::PhotoUpload's proven presigned-PUT
  # pattern rather than inventing a second upload/storage stack.
  #
  # `MAX_FILE_SIZE["video"]` is a TECHNICAL ABUSE CEILING, not a product-facing
  # video length/size limit:
  #   * WHAT it protects: R2 storage cost, upload/download bandwidth, and
  #     Solid Queue worker time (Media::ProcessMessageAttachmentJob downloads
  #     the whole object to run Media::VideoContainerValidator).
  #   * WHERE it is enforced: here, twice — the declared byte_size at upload
  #     authorization (`create_intent`), and the ACTUAL object size confirmed
  #     against R2 after upload (`build_verified!` -> `verify_object!`), the
  #     same "trust the object, not the client" pattern Profiles::PhotoUpload
  #     already uses for photos.
  #   * WHY 750MB: a typical modern phone shoots 4K video around
  #     130-170MB/minute; 750MB comfortably covers several minutes of ordinary
  #     footage. It is chosen to be far above anything a real dating-app chat
  #     video needs, so it is never visible to a legitimate user as a product
  #     limit — only an automated flood of deliberately huge files hits it.
  #
  # Chat media is participant-only content (never public/discoverable), so
  # there is deliberately no moderation status/visibility gate here, unlike
  # ProfilePhoto. Full structural video validation (Media::VideoContainerValidator)
  # is NOT run synchronously in this class — it requires downloading the whole
  # object, which must never happen on the Puma request thread. Only a cheap
  # magic-byte/box-header sniff runs here; the full box-tree walk runs in
  # Media::ProcessMessageAttachmentJob, off the request thread.
  class MessageAttachmentUpload
    ALLOWED_CONTENT_TYPES = {
      "image" => ProfilePhoto::ALLOWED_CONTENT_TYPES,
      "video" => %w[ video/mp4 video/quicktime ]
    }.freeze
    MAX_FILE_SIZE = {
      "image" => 20.megabytes,
      "video" => 750.megabytes
    }.freeze
    UPLOAD_URL_EXPIRES_IN = 15.minutes
    DELIVERY_URL_EXPIRES_IN = 5.minutes
    # Attachment-COUNT abuse limit, not a video-size substitute (see ticket
    # guidance): bounds fan-out of blob verification + async processing work
    # per message, independent of how large any one attachment is.
    MAX_ATTACHMENTS_PER_MESSAGE = 4

    Error = Class.new(StandardError)
    InvalidMediaKind = Class.new(Error)
    InvalidContentType = Class.new(Error)
    InvalidSize = Class.new(Error)
    InvalidUpload = Class.new(Error)
    AlreadyAttached = Class.new(Error)
    MissingObject = Class.new(Error)
    InvalidObject = Class.new(Error)
    TooManyAttachments = Class.new(Error)

    # Control plane: authorize a presigned PUT for one attachment (image,
    # video, or a video's poster image — a poster is just an image upload
    # against the same conversation, associated to its video at send time).
    def self.create_intent(user:, brand:, conversation_public_id:, media_kind:, filename:, byte_size:, checksum:,
      content_type:)
      access = ConversationAccess.find!(user:, brand:, conversation_public_id:)
      kind = normalize_media_kind(media_kind)

      content_type = content_type.to_s
      raise InvalidContentType unless ALLOWED_CONTENT_TYPES.fetch(kind).include?(content_type)

      byte_size = Integer(byte_size, exception: false)
      raise InvalidSize unless byte_size&.positive? && byte_size <= MAX_FILE_SIZE.fetch(kind)

      checksum = checksum.to_s
      raise InvalidUpload if checksum.blank?

      key = Media::ObjectKey.message_attachment_original(
        brand:, user:, conversation: access.conversation, content_type:
      )
      service_name = Media::StorageResolver.service_name(brand:)

      blob = ActiveStorage::Blob.create_before_direct_upload!(
        key:, filename: filename.to_s.presence || "attachment", byte_size:, checksum:, content_type:, service_name:
      )

      {
        signed_id: blob.signed_id,
        url: blob.service_url_for_direct_upload(expires_in: UPLOAD_URL_EXPIRES_IN),
        headers: blob.service_headers_for_direct_upload,
        expires_in: UPLOAD_URL_EXPIRES_IN.to_i,
        media_kind: kind,
        byte_size_limit: MAX_FILE_SIZE.fetch(kind),
        allowed_content_types: ALLOWED_CONTENT_TYPES.fetch(kind)
      }
    end

    # Data plane: verify one already-uploaded, not-yet-attached blob and build
    # (but do not save) a MessageAttachment. Saving happens inside
    # Messaging::SendMessage's single transaction alongside the Message itself,
    # so a message and its attachments are always created atomically.
    def self.build_verified!(brand:, position:, signed_id:, media_kind:, poster_signed_id: nil)
      kind = normalize_media_kind(media_kind)
      blob = find_blob!(brand:, signed_id:)
      verify_object!(blob:, media_kind: kind)

      attachment = MessageAttachment.new(
        brand:, media_kind: kind, position:, processing_state: :pending,
        content_type: blob.content_type, byte_size: blob.byte_size
      )
      attachment.original.attach(blob)
      attach_poster!(attachment:, brand:, signed_id: poster_signed_id) if poster_signed_id.present?
      attachment
    end

    def self.attach_poster!(attachment:, brand:, signed_id:)
      raise InvalidUpload, "poster is only valid for a video attachment" unless attachment.video?

      blob = find_blob!(brand:, signed_id:)
      verify_object!(blob:, media_kind: "image")
      attachment.poster.attach(blob)
    end

    def self.find_blob!(brand:, signed_id:)
      blob = ActiveStorage::Blob.find_signed(signed_id.to_s)
      raise InvalidUpload if blob.nil?
      raise InvalidUpload unless Media::StorageResolver.compatible_service?(brand:, service_name: blob.service_name)
      raise AlreadyAttached if blob.attachments.exists?

      blob
    end

    # Trust the object, not the client's declared metadata — same principle as
    # Profiles::PhotoUpload. Video gets a CHEAP magic-byte sniff only (reads a
    # few KB); the expensive full box-tree walk is deliberately deferred to
    # Media::ProcessMessageAttachmentJob so it never blocks a request.
    def self.verify_object!(blob:, media_kind:)
      service = blob.service
      raise MissingObject unless service.exist?(blob.key)

      limit = MAX_FILE_SIZE.fetch(media_kind)
      actual_size = object_byte_size(service, blob.key, limit)
      raise InvalidSize if actual_size.nil? || actual_size <= 0 || actual_size > limit

      if media_kind == "image"
        detected = Profiles::PhotoUpload.detect_image_type(service.download_chunk(blob.key, 0...16))
        raise InvalidObject if detected.nil?

        blob.update!(content_type: detected, byte_size: actual_size)
      else
        raise InvalidObject unless plausible_video_container?(service, blob.key)

        blob.update!(byte_size: actual_size)
      end
    end

    # Sniffs only the first few KB: the `ftyp` box is always first in a valid
    # MP4/QuickTime file, and its 4-byte type field always sits at offset 4.
    # This blocks an obviously-wrong upload (an executable or an image renamed
    # `.mp4`) cheaply; full structural/codec validation happens async.
    def self.plausible_video_container?(service, key)
      head = service.download_chunk(key, 0...4096).to_s.b
      head.bytesize >= 8 && head[4, 4] == "ftyp"
    end

    def self.object_byte_size(service, key, limit)
      if service.respond_to?(:bucket)
        service.bucket.object(key).content_length
      else
        service.download_chunk(key, 0...(limit + 1)).bytesize
      end
    rescue Errno::ENOENT
      nil
    end

    def self.normalize_media_kind(value)
      kind = value.to_s
      raise InvalidMediaKind unless ALLOWED_CONTENT_TYPES.key?(kind)

      kind
    end
  end
end
