module D8n
  module Platform
    module Capabilities
      module Match
        DEFINITIONS = [
          CapabilityDefinition.new(key: "match.eligibility", status: :available,
            implementations: %w[Matching::EligibilityScope Matching::ProfileParticipant]),
          CapabilityDefinition.new(key: "match.compatibility", status: :available,
            implementations: %w[Matching::Strategies::Hookus Matching::Strategies::DatezaV1]),
          CapabilityDefinition.new(key: "match.ranking", status: :available,
            implementations: %w[Matching::StrategyRegistry]),
          CapabilityDefinition.new(key: "match.interaction.like", status: :available,
            implementations: %w[Matching::LikeProfile]),
          CapabilityDefinition.new(key: "match.interaction.pass", status: :available,
            implementations: %w[Matching::PassProfile]),
          CapabilityDefinition.new(key: "match.relationship.create", status: :available,
            implementations: %w[Matching::LikeProfile Match]),
          CapabilityDefinition.new(key: "match.relationship.list", status: :available,
            implementations: %w[Matching::MatchList]),
          CapabilityDefinition.new(key: "match.relationship.unmatch", status: :planned),
          CapabilityDefinition.new(key: "match.hook", status: :available,
            implementations: %w[Hooks::SendHook Hooks::ReceivedInbox]),
          CapabilityDefinition.new(key: "match.hook_tonight", status: :available,
            implementations: %w[HookTonight::Activate HookTonight::Discovery])
        ].freeze

        def self.definitions = DEFINITIONS
      end
    end
  end
end
