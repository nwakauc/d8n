module Messaging
  class ConversationSerializer
    # `last_message` is optional: the conversation list passes the latest kept
    # message (fetched in one batched query) so the frontend list is useful; the
    # create path has none yet and passes nil. Sender is resolved from the
    # already-loaded participants, so no extra query is issued per card.
    def self.call(conversation:, viewer:, last_message: nil)
      {
        id: conversation.public_id,
        match_id: conversation.match.public_id,
        status: conversation.status,
        relationship_state: conversation.match.status,
        created_at: conversation.created_at.iso8601,
        profile: Profiles::PublicSerializer.call(profile: conversation.other_profile(viewer)),
        last_message: last_message && last_message_payload(conversation, last_message)
      }
    end

    def self.last_message_payload(conversation, message)
      sender = conversation.conversation_participants
        .find { |participant| participant.profile_id == message.sender_profile_id }&.profile
      {
        id: message.public_id,
        sender_id: sender&.public_id,
        body: message.body,
        created_at: message.created_at.iso8601
      }
    end
    private_class_method :last_message_payload
  end
end
