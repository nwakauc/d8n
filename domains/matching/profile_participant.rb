module Matching
  class ProfileParticipant
    def self.discoverable!(user:, brand:)
      user.reload
      profile = Profile.kept.active.visible.find_by(user:, brand:)
      preference = ProfilePreference.kept.find_by(profile:) if profile
      # Whether a member needs age preferences set to participate in discovery is
      # brand discovery policy (Date9ja's liquidity-first policy does not).
      # `interested_in` is always required — that is orientation, not a filter.
      age_preferences_ok = if discovery_policy(brand:).require_age_preferences
        preference&.min_age.present? && preference&.max_age.present?
      else
        true
      end
      available = profile && user.active? && user.deleted_at.nil? &&
        profile.brand_membership.active? && profile.brand_membership.deleted_at.nil? &&
        profile.birthdate.present? && profile.birthdate <= Profile::MINIMUM_AGE.years.ago.to_date && profile.gender.present? &&
        age_preferences_ok && preference&.interested_in&.any?

      raise InteractionError, :profile_unavailable unless available

      profile
    end

    def self.discovery_policy(brand:)
      D8n::Platform::BrandRegistry.fetch(brand:).interaction.eligibility_policy
    rescue D8n::Platform::BrandRegistry::UnsupportedBrand
      Matching::EligibilityPolicy::DEFAULT
    end
    private_class_method :discovery_policy

    def self.match_member!(user:, brand:)
      user.reload
      profile = Profile.kept.where.not(status: Profile.statuses.fetch("suspended")).find_by(user:, brand:)
      available = profile && user.active? && user.deleted_at.nil? &&
        profile.brand_membership.active? && profile.brand_membership.deleted_at.nil?

      raise InteractionError, :profile_unavailable unless available

      profile
    end
  end
end
