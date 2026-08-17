module Messaging
  # Signed, brand+viewer+conversation-bound cursor for message history. Mirrors
  # ConversationCursor. Ordering is newest-first by (created_at DESC, id DESC); the
  # cursor pages backward into older history. The internal row id is the stable
  # secondary key — safe to embed because the token is signed and opaque, and it is
  # a monotonic tiebreak when timestamps collide.
  class MessageCursor
    class Invalid < StandardError; end

    PURPOSE = "conversation-message-cursor"

    def self.encode(brand:, viewer:, conversation:, message:)
      verifier.generate(
        {
          brand: brand.slug,
          viewer: viewer.public_id,
          conversation: conversation.public_id,
          created_at: message.created_at.iso8601(6),
          id: message.id
        },
        purpose: PURPOSE
      )
    end

    def self.apply(scope:, value:, brand:, viewer:, conversation:)
      return scope if value.blank?

      payload = verifier.verify(value, purpose: PURPOSE).with_indifferent_access
      raise Invalid, "cursor is invalid" unless payload[:brand] == brand.slug &&
        payload[:viewer] == viewer.public_id &&
        payload[:conversation] == conversation.public_id

      created_at = Time.iso8601(payload.fetch(:created_at))
      id = Integer(payload.fetch(:id))

      scope.where(
        "messages.created_at < ? OR (messages.created_at = ? AND messages.id < ?)",
        created_at, created_at, id
      )
    rescue ActiveSupport::MessageVerifier::InvalidSignature, ArgumentError, KeyError, TypeError
      raise Invalid, "cursor is invalid"
    end

    def self.verifier
      Rails.application.message_verifier(PURPOSE)
    end
    private_class_method :verifier
  end
end
