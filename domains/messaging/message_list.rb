module Messaging
  # Participant-scoped, cursor-paginated message history for one conversation,
  # newest-first. Authorization is delegated to ConversationAccess, so outsiders,
  # cross-brand callers, and blocked pairs get a neutral `conversation_unavailable`
  # exactly like the rest of messaging. History is always bounded by `limit`.
  class MessageList
    DEFAULT_LIMIT = 30
    MAX_LIMIT = 100

    class InvalidLimit < StandardError; end

    Result = Data.define(:messages, :viewer, :conversation, :next_cursor)

    def self.call(user:, brand:, conversation_public_id:, cursor: nil, limit: nil)
      new(user:, brand:, conversation_public_id:, cursor:, limit:).call
    end

    def initialize(user:, brand:, conversation_public_id:, cursor:, limit:)
      @user = user
      @brand = brand
      @conversation_public_id = conversation_public_id
      @cursor = cursor
      @limit = normalize_limit(limit)
    end

    def call
      access = ConversationAccess.find!(user:, brand:, conversation_public_id:)
      scope = Message.kept.where(brand:, conversation: access.conversation)
        .order("messages.created_at DESC", "messages.id DESC")
      scope = MessageCursor.apply(scope:, value: cursor, brand:, viewer: access.viewer, conversation: access.conversation)
      messages = scope.includes(:sender_profile, :conversation).limit(limit + 1).to_a
      has_more = messages.length > limit
      messages = messages.first(limit)

      Result.new(
        messages:,
        viewer: access.viewer,
        conversation: access.conversation,
        next_cursor: has_more ? next_cursor(access, messages.last) : nil
      )
    end

    private

    attr_reader :user, :brand, :conversation_public_id, :cursor, :limit

    def next_cursor(access, message)
      MessageCursor.encode(brand:, viewer: access.viewer, conversation: access.conversation, message:)
    end

    def normalize_limit(value)
      return DEFAULT_LIMIT if value.blank?

      parsed = Integer(value, 10)
      raise InvalidLimit, "limit must be between 1 and #{MAX_LIMIT}" unless parsed.between?(1, MAX_LIMIT)

      parsed
    rescue ArgumentError, TypeError
      raise InvalidLimit, "limit must be between 1 and #{MAX_LIMIT}"
    end
  end
end
