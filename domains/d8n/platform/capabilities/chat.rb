module D8n
  module Platform
    module Capabilities
      module Chat
        DEFINITIONS = [
          CapabilityDefinition.new(key: "chat.conversation", status: :available,
            implementations: %w[Messaging::StartConversation Messaging::ConversationList]),
          CapabilityDefinition.new(key: "chat.message.text", status: :available,
            implementations: %w[Messaging::SendMessage Messaging::MessageList],
            dependencies: %w[chat.conversation]),
          CapabilityDefinition.new(key: "chat.message.media", status: :planned),
          CapabilityDefinition.new(key: "chat.read_state", status: :planned),
          CapabilityDefinition.new(key: "chat.realtime", status: :planned),
          CapabilityDefinition.new(key: "chat.voice", status: :planned),
          CapabilityDefinition.new(key: "chat.video", status: :planned)
        ].freeze

        def self.definitions = DEFINITIONS
      end
    end
  end
end
