module Messaging
  class ConversationCursor
    class Invalid < StandardError; end

    PURPOSE = "conversation-list-cursor"

    def self.encode(brand:, viewer:, conversation:)
      verifier.generate(
        {
          brand: brand.slug,
          viewer: viewer.public_id,
          created_at: conversation.created_at.iso8601(6),
          conversation: conversation.public_id
        },
        purpose: PURPOSE
      )
    end

    def self.apply(scope:, value:, brand:, viewer:)
      return scope if value.blank?

      payload = verifier.verify(value, purpose: PURPOSE).with_indifferent_access
      raise Invalid, "cursor is invalid" unless payload[:brand] == brand.slug && payload[:viewer] == viewer.public_id

      created_at = Time.iso8601(payload.fetch(:created_at))
      public_id = payload.fetch(:conversation).to_s
      raise Invalid, "cursor is invalid" unless public_id.match?(Profile::PUBLIC_ID_FORMAT)

      scope.where(
        "conversations.created_at < ? OR (conversations.created_at = ? AND conversations.public_id < ?)",
        created_at, created_at, public_id
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
