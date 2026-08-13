module Matching
  class ExclusionsScope
    def self.call(scope:, viewer:)
      scope.where.not(id: Like.kept.where(brand: viewer.brand, liker_profile: viewer).select(:liked_profile_id))
        .where.not(id: ProfilePass.kept.where(brand: viewer.brand, passer_profile: viewer).select(:passed_profile_id))
        .where.not(id: Match.kept.status_active.where(brand: viewer.brand, profile_a: viewer).select(:profile_b_id))
        .where.not(id: Match.kept.status_active.where(brand: viewer.brand, profile_b: viewer).select(:profile_a_id))
    end
  end
end
