module Profiles
  class CurrentLocation
    def self.upsert!(user:, brand:, attributes:)
      profile = Profile.kept.find_by!(user:, brand:)

      profile.with_lock do
        location = ProfileLocation.kept.find_or_initialize_by(profile:)
        location.assign_attributes(attributes)
        location.user = user
        location.brand = brand
        location.source = "device"
        location.save!
        location
      end
    end

    def self.soft_delete!(user:, brand:)
      profile = Profile.kept.find_by!(user:, brand:)

      profile.with_lock do
        location = ProfileLocation.kept.find_by(profile:)
        location&.update!(deleted_at: Time.current)
        Publication.unpublish_if_incomplete!(profile:)
        location
      end
    end
  end
end
