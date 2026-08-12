module Profiles
  class CurrentProfile
    def self.find(user:, brand:)
      Profile.kept.find_by(user:, brand:)
    end

    def self.upsert!(user:, brand:, attributes:)
      membership = BrandMembership.kept.find_by!(user:, brand:)
      profile = Profile.kept.find_or_initialize_by(user:, brand:)
      profile.brand_membership = membership
      profile.assign_attributes(attributes)
      profile.save!
      profile
    end
  end
end
