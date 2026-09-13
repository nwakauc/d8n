module Ai
  class ConversationSerializer
    def self.call(conversation:)
      {
        id: conversation.id,
        assistant_key: conversation.assistant_key,
        language: conversation.language,
        status: conversation.status,
        safety_status: conversation.safety_status,
        last_message_at: conversation.last_message_at&.iso8601,
        messages: conversation.ai_messages.map do |message|
          { id: message.id, role: message.role, content: message.content, created_at: message.created_at.iso8601 }
        end
      }
    end

    def self.summary(conversation:)
      first_message = conversation.ai_messages.role_user.order(:created_at, :id).first
      {
        id: conversation.id,
        assistant_key: conversation.assistant_key,
        language: conversation.language,
        last_message_at: conversation.last_message_at&.iso8601,
        preview: first_message&.content.to_s.truncate(120)
      }
    end
  end
end
