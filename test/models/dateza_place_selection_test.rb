require "test_helper"

# Covers Profiles::CurrentPlace end to end: server-resolved centroid coordinates
# (never client-submitted), country/brand scoping, and that a place-derived
# ProfileLocation feeds the exact same Matching path a raw device location does
# (Discovery, Find, and persistent-location semantics for old selections).
class DatezaPlaceSelectionTest < ActiveSupport::TestCase
  setup do
    @brand = Brand.create!(slug: "dateza", name: "DateZA")
    @country = Place.create!(kind: :country, code: "za", name: "South Africa", country_code: "ZA",
      latitude: 0, longitude: 0)
    @region = Place.create!(kind: :region, parent: @country, code: "western-cape", name: "Western Cape",
      country_code: "ZA", latitude: -33.9, longitude: 18.4)
    @city = Place.create!(kind: :city, parent: @region, code: "cape-town", name: "Cape Town",
      country_code: "ZA", latitude: -33.9249, longitude: 18.4241)
    @locality = Place.create!(kind: :locality, parent: @city, code: "sea-point", name: "Sea Point",
      country_code: "ZA", latitude: -33.9186, longitude: 18.3849)

    other_country = Place.create!(kind: :country, code: "na", name: "Namibia", country_code: "NA",
      latitude: 0, longitude: 0)
    @foreign_place = Place.create!(kind: :region, parent: other_country, code: "khomas", name: "Khomas",
      country_code: "NA", latitude: -22.5, longitude: 17.0)

    @user = User.create!
    @membership = BrandMembership.create!(brand: @brand, user: @user)
    @profile = Profile.create!(brand: @brand, user: @user, brand_membership: @membership,
      gender: "woman", birthdate: 30.years.ago.to_date, status: :active, visibility: :visible)
    ProfilePreference.create!(brand: @brand, user: @user, profile: @profile,
      interested_in: [ "man" ], min_age: 25, max_age: 40, max_distance_km: 50)
  end

  test "selecting a locality persists the server-resolved centroid, never a client value" do
    location = Profiles::CurrentPlace.select!(
      user: @user, brand: @brand, place_id: @locality.id, country_codes: %w[ ZA ]
    )

    assert_equal @locality, location.place
    assert_equal @locality.latitude, location.latitude
    assert_equal @locality.longitude, location.longitude
    assert_equal "place", location.source
  end

  test "rejects a nonexistent place id" do
    assert_raises(Profiles::CurrentPlace::InvalidPlace) do
      Profiles::CurrentPlace.select!(user: @user, brand: @brand, place_id: -1, country_codes: %w[ ZA ])
    end
  end

  test "rejects a place outside the brand's configured countries" do
    assert_raises(Profiles::CurrentPlace::InvalidPlace) do
      Profiles::CurrentPlace.select!(
        user: @user, brand: @brand, place_id: @foreign_place.id, country_codes: %w[ ZA ]
      )
    end
  end

  test "rejects selecting a country-level place directly" do
    assert_raises(Profiles::CurrentPlace::InvalidPlace) do
      Profiles::CurrentPlace.select!(user: @user, brand: @brand, place_id: @country.id, country_codes: %w[ ZA ])
    end
  end

  test "a place-derived location remains eligible for Discovery and Find long after selection" do
    Profiles::CurrentPlace.select!(user: @user, brand: @brand, place_id: @city.id, country_codes: %w[ ZA ])
    ProfileLocation.kept.find_by(profile: @profile).update!(captured_at: 60.days.ago)

    candidate_user = User.create!
    candidate_membership = BrandMembership.create!(brand: @brand, user: candidate_user)
    candidate = Profile.create!(brand: @brand, user: candidate_user, brand_membership: candidate_membership,
      gender: "man", birthdate: 30.years.ago.to_date, status: :active, visibility: :visible)
    ProfilePreference.create!(brand: @brand, user: candidate_user, profile: candidate,
      interested_in: [ "woman" ], min_age: 25, max_age: 40, max_distance_km: 50)
    ProfileLocation.create!(profile: candidate, user: candidate_user, brand: @brand,
      latitude: @city.latitude, longitude: @city.longitude, accuracy_meters: 20, source: "device",
      captured_at: 200.days.ago)

    discovery = Matching::Discovery.call(user: @user, brand: @brand)
    find = Matching::Find::Search.call(user: @user, brand: @brand)

    assert_equal [ candidate.id ], discovery.profiles.map(&:id)
    assert_equal [ candidate.id ], find.profiles.map(&:id)
  end
end
