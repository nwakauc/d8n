module Matching
  class ProfileParticipant
    def self.discoverable!(user:, brand:)
      user.reload
      profile = Profile.kept.active.visible.find_by(user:, brand:)
      preference = ProfilePreference.kept.find_by(profile:) if profile
      available = profile && user.active? && user.deleted_at.nil? &&
        profile.brand_membership.active? && profile.brand_membership.deleted_at.nil? &&
        profile.birthdate.present? && profile.birthdate <= Profile::MINIMUM_AGE.years.ago.to_date && profile.gender.present? &&
        preference&.min_age.present? && preference.max_age.present? && preference.interested_in.any?

      raise InteractionError, :profile_unavailable unless available

      profile
    end

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
