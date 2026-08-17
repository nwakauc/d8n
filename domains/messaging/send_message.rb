module Messaging
  # Appends one plain-text message to a conversation after re-authorizing the
  # sender through ConversationAccess (participant, active match, availability,
  # both block directions). Body is NFC-normalized untrusted input: whitespace-only
  # is rejected, length is bounded, and Unicode/emoji is preserved verbatim.
  #
  # Beta accepts at-least-once client sends: there is no client idempotency key, so
  # a retried request creates a second message. This is deliberate for the beta
  # scale — a `client_token` dedupe column is recorded as an early-beta follow-up.
  class SendMessage
    Result = Data.define(:message, :viewer)

    def self.call(user:, brand:, conversation_public_id:, body:)
      access = ConversationAccess.find!(user:, brand:, conversation_public_id:)
      content = normalize(body)
      raise MessageError, :message_blank if content.blank?
      raise MessageError, :message_too_long if content.length > Message::MAX_BODY_LENGTH

      message = Message.create!(
        brand:, conversation: access.conversation, sender_profile: access.viewer, body: content
      )
      Result.new(message:, viewer: access.viewer)
    end

    def self.normalize(raw)
      raw.to_s.unicode_normalize(:nfc)
    end
    private_class_method :normalize
  end
end
