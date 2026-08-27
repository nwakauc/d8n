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
          # Read (incoming/outgoing) shares this same key with the write action
          # (create), matching how match.opener/match.hook already cover
          # send+inbox+reply+decline under one key — a brand that can create
          # Likes can read its own Like relationships; no separate policy
          # question exists between the two.
          CapabilityDefinition.new(key: "match.interaction.like", status: :available,
            implementations: %w[Matching::LikeProfile Matching::IncomingLikes Matching::OutgoingLikes]),
          CapabilityDefinition.new(key: "match.interaction.pass", status: :available,
            implementations: %w[Matching::PassProfile]),
          CapabilityDefinition.new(key: "match.relationship.create", status: :available,
            implementations: %w[Matching::LikeProfile Match]),
          CapabilityDefinition.new(key: "match.relationship.list", status: :available,
            implementations: %w[Matching::MatchList]),
          # Distinct capability from match.relationship.list (viewing a match
          # does not imply the ability to end it) and deliberately does not
          # touch Trust::BlockProfile — Unmatch never creates a ProfileBlock;
          # Block remains the stronger, separate safety action.
          CapabilityDefinition.new(key: "match.relationship.unmatch", status: :available,
            implementations: %w[Matching::Unmatch]),
          CapabilityDefinition.new(key: "match.hook", status: :available,
            implementations: %w[Hooks::SendHook Hooks::ReceivedInbox]),
          # D8N Opener: the same one-shot-opener/reply-unlocks-chat engine as
          # match.hook, exposed under generic naming for brands (DateZA and
          # future brands) whose product does not use the "Hook" label. Shares
          # every implementation class with match.hook; only the brand's
          # OpenerConfiguration (catalog_required, allowance) differs.
          CapabilityDefinition.new(key: "match.opener", status: :available,
            implementations: %w[Hooks::SendHook Hooks::ReceivedInbox]),
          CapabilityDefinition.new(key: "match.hook_tonight", status: :available,
            implementations: %w[HookTonight::Activate HookTonight::Discovery])
        ].freeze

        def self.definitions = DEFINITIONS
      end
    end
  end
end
