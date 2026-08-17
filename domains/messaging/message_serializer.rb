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
        created_at: message.created_at.iso8601
      }
    end
  end
end
