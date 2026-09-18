module Messaging
  class ReadState
    class InvalidMessages < StandardError; end

    def self.unread_scope(user:, brand:)
      viewer = Profile.kept.find_by(user:, brand:)
      return Message.none unless viewer

      conversations = ConversationList.available_scope(viewer:, brand:).select(:id)
      Message.kept.where(brand:, conversation_id: conversations)
        .where.not(sender_profile_id: viewer.id)
        .where.not(id: MessageRead.where(brand:, profile: viewer).select(:message_id))
    end

    def self.snapshot(user:, brand:)
      counts = unread_scope(user:, brand:).joins(:conversation).group("conversations.public_id").count
      { unread_message_count: counts.values.sum, conversations: counts }
    end

    # Conversation lists already contain an authorized set of records. Count
    # unread rows for that set directly instead of rebuilding the full
    # availability and block-policy scope used by the global badge.
    def self.conversation_counts(user:, brand:, conversations:)
      viewer = Profile.kept.find_by(user:, brand:)
      return {} unless viewer

      ids = conversations.map(&:id)
      return {} if ids.empty?

      Message.kept.where(brand:, conversation_id: ids)
        .where.not(sender_profile_id: viewer.id)
        .where.not(id: MessageRead.where(brand:, profile: viewer).select(:message_id))
        .joins(:conversation)
        .group("conversations.public_id").count
    end

    # Only messages the client actually displayed are acknowledged. A concurrent
    # incoming message is never swept into a broad "read everything" update.
    def self.mark!(user:, brand:, conversation_public_id:, message_ids:)
      unless message_ids.is_a?(Array) && message_ids.size.between?(1, 100) &&
          message_ids.all? { |id| id.is_a?(String) }
        raise InvalidMessages
      end
      access = ConversationAccess.find!(user:, brand:, conversation_public_id:, allow_ended: true)
      messages = Message.kept.where(brand:, conversation: access.conversation, public_id: message_ids.uniq)
      raise InvalidMessages unless messages.count == message_ids.uniq.size

      incoming = messages.where.not(sender_profile_id: access.viewer.id)
      now = Time.current
      MessageRead.transaction do
        rows = incoming.pluck(:id).map do |id|
          { brand_id: brand.id, profile_id: access.viewer.id, message_id: id, read_at: now }
        end
        MessageRead.insert_all(rows, unique_by: [ :profile_id, :message_id ]) if rows.any?
        Notifications::Inbox.scope(brand:, user:).unread
          .where("payload #>> '{target,type}' = ?", "conversation")
          .where("payload #>> '{target,id}' = ?", access.conversation.public_id)
          .where("payload #>> '{target,message_id}' IN (?)", incoming.pluck(:public_id))
          .update_all(read_at: now, updated_at: now)
      end
      Realtime::MemberEvents.publish(brand_id: brand.id, user_id: user.id, type: "read_state_changed")
      snapshot(user:, brand:)
    end
  end
end
