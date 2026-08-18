module Matching
  class ExclusionsScope
    def self.call(scope:, viewer:)
      scope.where.not(id: Like.kept.where(brand: viewer.brand, liker_profile: viewer).select(:liked_profile_id))
        .where.not(id: ProfilePass.kept.where(brand: viewer.brand, passer_profile: viewer).select(:passed_profile_id))
        .where.not(id: Match.kept.status_active.where(brand: viewer.brand, profile_a: viewer).select(:profile_b_id))
        .where.not(id: Match.kept.status_active.where(brand: viewer.brand, profile_b: viewer).select(:profile_a_id))
        # A live 🔥 Hook (either direction) takes the pair out of discovery until
        # it resolves: an outgoing one is awaiting their reply, an incoming one is
        # awaiting the viewer's. Once it lapses/declines/accepts the pair follows
        # normal rules again (an accepted Hook becomes a Match, already excluded).
        .where.not(id: Hook.live.where(brand: viewer.brand, sender_profile: viewer).select(:recipient_profile_id))
        .where.not(id: Hook.live.where(brand: viewer.brand, recipient_profile: viewer).select(:sender_profile_id))
    end
  end
end
