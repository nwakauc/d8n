module Profiles
  class CurrentLocation
    # A place-selection brand's UX presents location as an AREA (see
    # Profiles::CurrentPlace), not an exact pin, so a raw device-GPS submission
    # on the same brand is snapped down to the same coarse, locality-level
    # granularity the Place path already produces — no client ever needs (or
    # should be able to store) an exact resident coordinate on these brands.
    # Precise-pin brands (e.g. HookUs, which has no place_selection capability)
    # are unaffected and keep exact device precision.
    PRECISION_HARDENED_DECIMAL_PLACES = 2
    PRECISION_HARDENED_MIN_ACCURACY_METERS = Profiles::CurrentPlace::ACCURACY_METERS_BY_KIND.fetch("locality")

    def self.find(user:, brand:)
      profile = Profile.kept.find_by(user:, brand:)
      return if profile.blank?

      ProfileLocation.kept.includes(:place).find_by(profile:)
    end

    def self.upsert!(user:, brand:, attributes:)
      profile = Profile.kept.find_by!(user:, brand:)

      profile.with_lock do
        location = ProfileLocation.kept.find_or_initialize_by(profile:)
        location.assign_attributes(harden_precision(brand:, attributes:))
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

    def self.harden_precision(brand:, attributes:)
      return attributes unless place_selection_brand?(brand)

      hardened = attributes.to_h.symbolize_keys
      hardened[:latitude] = round_coordinate(hardened[:latitude])
      hardened[:longitude] = round_coordinate(hardened[:longitude])
      if hardened[:accuracy_meters].present?
        hardened[:accuracy_meters] = [ hardened[:accuracy_meters].to_i, PRECISION_HARDENED_MIN_ACCURACY_METERS ].max
      end
      hardened
    end
    private_class_method :harden_precision

    def self.round_coordinate(value)
      return value if value.blank?

      BigDecimal(value.to_s).round(PRECISION_HARDENED_DECIMAL_PLACES)
    end
    private_class_method :round_coordinate

    def self.place_selection_brand?(brand)
      D8n::Platform::BrandRegistry.fetch(brand:).capability_enabled?("profile.location.place_selection")
    rescue D8n::Platform::BrandRegistry::UnsupportedBrand
      false
    end
    private_class_method :place_selection_brand?
  end
end
