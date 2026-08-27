module Messaging
  # "Delete for everyone" for one attachment the caller sent. Deliberately
  # attachment-granularity, not whole-message: a mixed text+media message keeps
  # its text and its other attachments; only the deleted attachment disappears
  # (shown as a removed state — see Messaging::MessageSerializer). The sender's
  # OWN attachment only — a recipient can never delete another profile's media
  # (enforced via `message.sender_profile_id == viewer.id`, not by trusting any
  # client-supplied flag).
  class DeleteAttachment
    Result = Data.define(:attachment)

    def self.call(user:, brand:, conversation_public_id:, message_public_id:, attachment_public_id:)
      access = ConversationAccess.find!(user:, brand:, conversation_public_id:)

      message = access.conversation.messages.kept.find_by(public_id: message_public_id)
      raise AccessError, :message_unavailable if message.blank?
      raise AccessError, :attachment_not_owned unless message.sender_profile_id == access.viewer.id

      attachment = message.message_attachments.kept.find_by(public_id: attachment_public_id)
      raise AccessError, :attachment_unavailable if attachment.blank?

      attachment.update!(deleted_at: Time.current)
      purge!(attachment)
      Result.new(attachment:)
    end

    # A video attachment's `rendition` points at the SAME blob as `original`
    # whenever Media::VideoProcessor determined no transcode was needed (see
    # its class comment). Purging every attached slot independently would
    # purge that shared blob out from under the still-attached second
    # reference, so each blob is purged (or detached, if a duplicate
    # reference) exactly once regardless of how many slots point at it.
    def self.purge!(attachment)
      slots = [ attachment.original, attachment.rendition, attachment.download_rendition, attachment.poster ]
        .select(&:attached?)
      seen_blob_ids = Set.new

      slots.each do |attached|
        blob_id = attached.blob.id
        if seen_blob_ids.include?(blob_id)
          attached.detach
        else
          seen_blob_ids << blob_id
          attached.purge_later
        end
      end
    end
  end
end
