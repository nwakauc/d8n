module Profiles
  class CurrentProfile
    def self.find(user:, brand:)
      Profile.kept.find_by(user:, brand:)
    end

    def self.upsert!(user:, brand:, attributes:)
      membership = BrandMembership.kept.find_by!(user:, brand:)
      profile = Profile.kept.find_or_initialize_by(user:, brand:)

      if profile.persisted?
        profile.with_lock { update_profile!(profile:, membership:, attributes:) }
      else
        update_profile!(profile:, membership:, attributes:)
      end

      profile
    end

    def self.update_profile!(profile:, membership:, attributes:)
      profile.brand_membership = membership
      profile.assign_attributes(attributes)
      profile.save!
      Publication.unpublish_if_incomplete!(profile:)
    end
    private_class_method :update_profile!
  end
end
