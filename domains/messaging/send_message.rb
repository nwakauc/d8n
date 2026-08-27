module Messaging
  # Appends one message — text, media, or both — to a conversation after
  # re-authorizing the sender through ConversationAccess (participant, active
  # match, availability, both block directions). Body is NFC-normalized
  # untrusted input; a body is only required when there are no attachments (see
  # Message#body_or_attachment_present).
  #
  # "Attach" and "send" are deliberately the SAME operation: an attachment's
  # blob is only verified and turned into a MessageAttachment here, inside the
  # same transaction that creates the Message. There is no separate
  # "attached-but-not-yet-in-a-message" state to track or clean up — a
  # conversation is the only thing that gives an attachment its authorization
  # context, and a Message is the only thing that can hold one, so folding
  # attach into send is the smallest coherent contract (see D8N Chat Media
  # ticket's own preference for the simpler design where the model allows it).
  #
  # Beta accepts at-least-once client sends: there is no client idempotency key, so
  # a retried request creates a second message. This is deliberate for the beta
  # scale — a `client_token` dedupe column is recorded as an early-beta follow-up.
  class SendMessage
    Result = Data.define(:message, :viewer)

    def self.call(user:, brand:, conversation_public_id:, body: nil, attachment_uploads: nil)
      access = ConversationAccess.find!(user:, brand:, conversation_public_id:)
      uploads = normalize_uploads(attachment_uploads)
      content = prepare_body(body, uploads)

      message = nil
      Profile.transaction do
        message = Message.new(brand:, conversation: access.conversation, sender_profile: access.viewer, body: content)
        uploads.each_with_index do |upload, index|
          message.message_attachments << MessageAttachmentUpload.build_verified!(
            brand:, position: index,
            signed_id: upload.fetch(:signed_id), media_kind: upload.fetch(:media_kind),
            poster_signed_id: upload[:poster_signed_id]
          )
        end
        message.save!
        recipient = access.match.other_profile(access.viewer)
        Notifications::EventPublisher.message_received!(message:, recipient:)
      end

      enqueue_processing(message)
      Result.new(message:, viewer: access.viewer)
    end

    def self.prepare_body(raw, uploads)
      return nil if raw.to_s.strip.blank? && uploads.any?

      MessageBody.prepare(raw)
    end
    private_class_method :prepare_body

    def self.normalize_uploads(raw)
      uploads = Array(raw)
      if uploads.size > MessageAttachmentUpload::MAX_ATTACHMENTS_PER_MESSAGE
        raise MessageAttachmentUpload::TooManyAttachments
      end

      uploads
    end
    private_class_method :normalize_uploads

    def self.enqueue_processing(message)
      message.message_attachments.each do |attachment|
        Media::ProcessMessageAttachmentJob.perform_later(attachment.id)
      end
    end
    private_class_method :enqueue_processing
  end
end
