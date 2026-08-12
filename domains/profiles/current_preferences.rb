module Profiles
  class CurrentPreferences
    def self.find(user:, brand:)
      ProfilePreference.kept.find_by(user:, brand:)
    end

    def self.upsert!(user:, brand:, attributes:)
      profile = Profile.kept.find_by!(user:, brand:)
      preference = ProfilePreference.kept.find_or_initialize_by(user:, brand:)
      preference.profile = profile
      preference.assign_attributes(attributes)
      preference.save!
      preference
    end
  end
end
