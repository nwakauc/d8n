module D8n
  module Platform
    module Capabilities
      module Ai
        DEFINITIONS = [
          CapabilityDefinition.new(key: "ai.dating_assistant", status: :available,
            implementations: %w[Ai::ConversationService Ai::ProviderRegistry Ai::SafetyTriage]),
          CapabilityDefinition.new(key: "ai.matchmaker", status: :planned),
          CapabilityDefinition.new(key: "ai.profile_assistant", status: :planned),
          CapabilityDefinition.new(key: "ai.safety_assistant", status: :planned),
          CapabilityDefinition.new(key: "ai.moderation_assistant", status: :planned)
        ].freeze

        def self.definitions = DEFINITIONS
      end
    end
  end
end
