module Matching
  class ExclusionsScope
    def self.call(scope:, viewer:, contributors: [])
      base = scope.where.not(id: Like.kept.where(brand: viewer.brand, liker_profile: viewer).select(:liked_profile_id))
        .where.not(id: ProfilePass.kept.where(brand: viewer.brand, passer_profile: viewer).select(:passed_profile_id))
        .where.not(id: Match.kept.status_active.where(brand: viewer.brand, profile_a: viewer).select(:profile_b_id))
        .where.not(id: Match.kept.status_active.where(brand: viewer.brand, profile_b: viewer).select(:profile_a_id))

      Array(contributors).reduce(base) do |current_scope, contributor|
        contributor.call(scope: current_scope, viewer:)
      end
    end
  end
end
