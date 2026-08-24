module Hooks
  class DiscoveryExclusion
    def self.call(scope:, viewer:)
      scope
        .where.not(
          id: Hook.live.where(brand: viewer.brand, sender_profile: viewer).select(:recipient_profile_id)
        )
        .where.not(
          id: Hook.live.where(brand: viewer.brand, recipient_profile: viewer).select(:sender_profile_id)
        )
    end
  end
end
