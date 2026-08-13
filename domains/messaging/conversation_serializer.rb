module Messaging
  class ConversationSerializer
    def self.call(conversation:, viewer:)
      {
        id: conversation.public_id,
        match_id: conversation.match.public_id,
        status: conversation.status,
        created_at: conversation.created_at.iso8601,
        profile: Profiles::PublicSerializer.call(profile: conversation.other_profile(viewer))
      }
    end
  end
end
