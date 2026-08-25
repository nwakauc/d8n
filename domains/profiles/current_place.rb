module Profiles
  # Resolves a member's selected Place into the SAME authoritative
  # ProfileLocation row Profiles::CurrentLocation writes to, so Matching never
  # needs to know places exist — it always reads plain lat/lon. The server
  # resolves the place's centroid; a client can never submit its own
  # coordinates through this path.
  class CurrentPlace
    class InvalidPlace < StandardError; end

    # Rough radius implied by each granularity, so distance filtering degrades
    # honestly for a coarser selection instead of pretending locality-level
    # precision. Not a real measurement — a documented default per kind.
    ACCURACY_METERS_BY_KIND = {
      "region" => 80_000,
      "city" => 15_000,
      "locality" => 3_000
    }.freeze

    def self.select!(user:, brand:, place_id:, country_codes:)
      profile = Profile.kept.find_by!(user:, brand:)
      place = Place.selectable.find_by(id: place_id)
      raise InvalidPlace if place.blank? || place.country? || country_codes.exclude?(place.country_code)

      profile.with_lock do
        location = ProfileLocation.kept.find_or_initialize_by(profile:)
        location.assign_attributes(
          latitude: place.latitude,
          longitude: place.longitude,
          accuracy_meters: ACCURACY_METERS_BY_KIND.fetch(place.kind, 50_000),
          captured_at: Time.current,
          source: "place",
          place:
        )
        location.user = user
        location.brand = brand
        location.save!
        location
      end
    end
  end
end
