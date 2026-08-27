module Profiles
  class CurrentLocation
    def self.find(user:, brand:)
      profile = Profile.kept.find_by(user:, brand:)
      return if profile.blank?

      ProfileLocation.kept.includes(:place).find_by(profile:)
    end

    def self.upsert!(user:, brand:, attributes:)
      profile = Profile.kept.find_by!(user:, brand:)

      profile.with_lock do
        location = ProfileLocation.kept.find_or_initialize_by(profile:)
        location.assign_attributes(attributes)
        location.user = user
        location.brand = brand
        location.source = "device"
        # A raw device/manual coordinate always supersedes any earlier Place
        # selection — without this, a member who switches from a Place-based
        # location back to device GPS would keep the stale place_id from their
        # old selection, so callers (e.g. the owner location readback) would
        # report a place name that no longer matches the coordinates actually
        # in use by Matching.
        location.place = nil
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
