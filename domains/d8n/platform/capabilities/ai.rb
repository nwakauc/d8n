module D8n
  module Platform
    module Capabilities
      module Ai
        DEFINITIONS = %w[
          ai.matchmaker
          ai.profile_assistant
          ai.dating_assistant
          ai.safety_assistant
          ai.moderation_assistant
        ].map { |key| CapabilityDefinition.new(key:, status: :planned) }.freeze

        def self.definitions = DEFINITIONS
      end
    end
  end
end
