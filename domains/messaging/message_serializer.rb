module Messaging
  # User-facing message shape. `sender_id` is the author's profile public id — the
  # two participants are known, so the client identifies its own messages by
  # comparing against the counterpart profile id already present on the
  # conversation. No internal ids, moderation metadata, or storage details leak.
  class MessageSerializer
    def self.call(message:)
      {
        id: message.public_id,
        conversation_id: message.conversation.public_id,
        sender_id: message.sender_profile.public_id,
        body: message.body,
        attachments: message.message_attachments.map { |attachment| attachment_payload(attachment) },
        created_at: message.created_at.iso8601,
        reply_to: reply_to_payload(message)
      }
    end

    # Always rendered from the frozen reply_snapshot captured at send time —
    # never by re-reading the original message's live body/attachments — so
    # the preview keeps working even if the original was since deleted. Only
    # `deleted` reflects live state (a cheap FK-backed association check), so
    # the client can gray out a preview whose original is gone without the
    # preview text itself changing underneath it.
    def self.reply_to_payload(message)
      return nil if message.reply_to_message_id.blank?

      snapshot = message.reply_snapshot
      {
        id: snapshot["message_public_id"],
        sender_id: snapshot["sender_profile_id"],
        message_type: snapshot["message_type"],
        body_excerpt: snapshot["body_excerpt"],
        deleted: message.reply_to_message.blank? || !message.reply_to_message.kept?
      }
    end
    private_class_method :reply_to_payload

    # Private media is served through short-lived signed retrieval URLs straight
    # from R2 — never a permanent public object path, never proxied through
    # Puma. `view_url`/`download_url` only appear once a safe rendition exists
    # AND the attachment has not been deleted; the recipient never sees a
    # broken half-processed attachment as if it were ready (see
    # domains/media/photo_policy.rb for the equivalent profile-photo invariant).
    def self.attachment_payload(attachment)
      payload = {
        id: attachment.public_id,
        media_kind: attachment.media_kind,
        processing_state: attachment.processing_state,
        deleted: !attachment.kept?,
        content_type: attachment.content_type,
        byte_size: attachment.byte_size,
        width: attachment.width,
        height: attachment.height,
        duration_seconds: attachment.duration_seconds&.to_f
      }
      return payload unless attachment.deliverable?

      # Inline view/play always uses the safe, bandwidth-friendly RENDITION
      # (never forces a full-quality download just to look at something).
      #
      # Explicit "download/save":
      #   * image — the SANITIZED, metadata-stripped `download_rendition`
      #     (D8N Chat Media 1.1). The recipient never receives the sender's
      #     untouched original, which could carry EXIF GPS/device metadata;
      #     see MessageAttachment's class comment.
      #   * video — still the ORIGINAL, full-quality bytes the sender
      #     uploaded. Compressed video does not carry the same per-file EXIF
      #     GPS risk a camera photo does, so this remains the deliberate
      #     "authorized download of the real upload" product decision (see
      #     MessageAttachmentUpload's class comment on why the original is
      #     retained rather than purged).
      payload.merge(
        view_url: delivery_url(attachment.rendition, disposition: :inline),
        download_url: delivery_url(download_source(attachment), disposition: :attachment, filename: download_filename(attachment)),
        poster_url: poster_url(attachment)
      )
    end
    private_class_method :attachment_payload

    def self.download_source(attachment)
      attachment.image? ? attachment.download_rendition : attachment.original
    end
    private_class_method :download_source

    def self.delivery_url(attached, disposition:, filename: nil)
      options = { expires_in: Messaging::MessageAttachmentUpload::DELIVERY_URL_EXPIRES_IN, disposition: }
      options[:filename] = ActiveStorage::Filename.new(filename) if filename.present?
      attached.url(**options)
    end
    private_class_method :delivery_url

    def self.poster_url(attachment)
      return nil unless attachment.poster.attached?

      delivery_url(attachment.poster, disposition: :inline)
    end
    private_class_method :poster_url

    def self.download_filename(attachment)
      extension = download_source(attachment).blob.filename.extension_with_delimiter
      "d8n-#{attachment.media_kind}-#{attachment.public_id}#{extension}"
    end
    private_class_method :download_filename
  end
end
