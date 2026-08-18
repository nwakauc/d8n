module Matching
  # The FUNDAMENTAL visibility/safety rules that decide whether one profile may
  # be seen by another AT ALL — independent of discovery ranking or mutual dating
  # preferences.
  #
  # These are the rules that must never be bypassed: brand isolation, the
  # active/visible lifecycle (which also excludes suspended, closed, discarded,
  # and inactive accounts), a minimum-age gate, and blocks in EITHER direction.
  #
  # Reused as the base scope by both discovery (Matching::EligibilityScope, which
  # then layers reciprocal gender/age/distance ranking on top) and direct profile
  # retrieval (Profiles::PublicProfile). Sharing one definition guarantees a
  # direct profile link can never bypass a rule discovery enforces, while a change
  # to ranking or dating preferences can never break an otherwise valid link.
  class VisibilityScope
    def self.call(brand:, viewer:)
      scope = brand.profiles.kept.active.visible
        .where.not(id: viewer.id)
        .joins(:user, :brand_membership, :profile_preference)
        .merge(User.kept.active)
        .merge(BrandMembership.kept.active)
        .where(profile_preferences: { deleted_at: nil })
        .where.not(birthdate: nil)
        .where("profiles.birthdate <= ?", Profile::MINIMUM_AGE.years.ago.to_date)

      Trust::BlockPolicy.exclude_profiles(scope:, viewer:)
    end
  end
end
