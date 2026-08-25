require "test_helper"

class Api::V1::ProfilePlacesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @brand = Brand.create!(slug: "dateza", name: "DateZA")
    Profiles::DatezaProfileCatalog.install!(brand: @brand)
    BrandDomain.create!(brand: @brand, host: "dateza.test")
    Geography::SouthAfricaCatalog.install!
    @locality = Place.kept.find_by!(code: "sea-point")
    other_country = Place.create!(kind: :country, code: "na", name: "Namibia", country_code: "NA",
      latitude: 0, longitude: 0)
    @foreign_place = Place.create!(kind: :region, parent: other_country, code: "khomas", name: "Khomas",
      country_code: "NA", latitude: -22.5, longitude: 17.0)

    @user = User.create!(first_name: "Thandi", last_name: "Mokoena")
    @membership = BrandMembership.create!(brand: @brand, user: @user)
    @profile = Profile.create!(brand: @brand, user: @user, brand_membership: @membership,
      display_name: "Thandi", birthdate: 28.years.ago.to_date, gender: "woman", country_code: "ZA",
      city: "Cape Town", bio: "Hello there.", smoking: "never", drinking: "never")
    ProfilePreference.create!(brand: @brand, user: @user, profile: @profile,
      min_age: 25, max_age: 40, interested_in: [ "man" ], max_distance_km: 50)
    Profiles::OptionSelections.replace!(
      profile: @profile,
      selections: {
        relationship_intent: [ "long_term_relationship" ], has_children: [ "no" ], wants_children: [ "yes" ],
        religion_importance: [ "not_important" ], social_style: [ "introverted" ], meeting_pace: [ "meet_soon" ]
      }
    )
    photo = ProfilePhoto.new(brand: @brand, user: @user, profile: @profile)
    photo.image.attach(
      io: Rails.root.join("test/fixtures/files/profile_photo.png").open,
      filename: "profile_photo.png", content_type: "image/png"
    )
    photo.save!

    @token, = Session.issue!(brand: @brand, user: @user)
    host! "dateza.test"
  end

  test "selecting a locality configures the location and exposes a safe display path, no coordinates" do
    put "/api/v1/profile/place", headers: bearer_headers(@token), params: { place_id: @locality.id }

    assert_response :success
    body = JSON.parse(response.body).fetch("location")
    assert_equal true, body.fetch("configured")
    assert_equal "Sea Point, Cape Town, Western Cape", body.dig("place", "display_path")
    assert_not body.key?("latitude")
    assert_not body.key?("longitude")
    assert_not_includes response.body, @locality.latitude.to_s
    assert_not_includes response.body, @locality.longitude.to_s
  end

  test "a client-submitted latitude/longitude is ignored — only the server-resolved place centroid persists" do
    put "/api/v1/profile/place", headers: bearer_headers(@token),
      params: { place_id: @locality.id, latitude: 0.0, longitude: 0.0 }

    assert_response :success
    location = ProfileLocation.kept.find_by(profile: @profile)
    assert_equal @locality.latitude, location.latitude
    assert_equal @locality.longitude, location.longitude
  end

  test "rejects an unsupported-country place" do
    put "/api/v1/profile/place", headers: bearer_headers(@token), params: { place_id: @foreign_place.id }

    assert_response :unprocessable_entity
    assert_equal({ "error" => "invalid_place" }, JSON.parse(response.body))
  end

  test "rejects a nonexistent place" do
    put "/api/v1/profile/place", headers: bearer_headers(@token), params: { place_id: -1 }

    assert_response :unprocessable_entity
  end

  test "GET /api/v1/profile reports location.configured true after place selection" do
    put "/api/v1/profile/place", headers: bearer_headers(@token), params: { place_id: @locality.id }

    get "/api/v1/profile", headers: bearer_headers(@token)

    body = JSON.parse(response.body).fetch("profile").fetch("location")
    assert_equal true, body.fetch("configured")
    assert_equal "Sea Point, Cape Town, Western Cape", body.dig("place", "display_path")
  end

  test "publication succeeds once a place is selected, and fails without one" do
    post "/api/v1/profile/publication", headers: bearer_headers(@token)
    assert_response :unprocessable_entity
    assert_includes JSON.parse(response.body).dig("completion", "missing"), "location"

    put "/api/v1/profile/place", headers: bearer_headers(@token), params: { place_id: @locality.id }
    post "/api/v1/profile/publication", headers: bearer_headers(@token)

    assert_response :success
    assert @profile.reload.active?
  end

  test "removing the location after publishing via place selection unpublishes the profile" do
    put "/api/v1/profile/place", headers: bearer_headers(@token), params: { place_id: @locality.id }
    post "/api/v1/profile/publication", headers: bearer_headers(@token)
    assert @profile.reload.active?

    delete "/api/v1/profile/location", headers: bearer_headers(@token)

    assert_response :success
    assert @profile.reload.draft?
    assert @profile.hidden?
  end

  test "a stale place-selected location remains eligible for Discovery/Find" do
    put "/api/v1/profile/place", headers: bearer_headers(@token), params: { place_id: @locality.id }
    post "/api/v1/profile/publication", headers: bearer_headers(@token)
    assert @profile.reload.active?
    ProfileLocation.kept.find_by(profile: @profile).update!(captured_at: 120.days.ago)

    candidate_user = User.create!
    candidate_membership = BrandMembership.create!(brand: @brand, user: candidate_user)
    candidate = Profile.create!(brand: @brand, user: candidate_user, brand_membership: candidate_membership,
      gender: "man", birthdate: 30.years.ago.to_date, status: :active, visibility: :visible)
    ProfilePreference.create!(brand: @brand, user: candidate_user, profile: candidate,
      interested_in: [ "woman" ], min_age: 25, max_age: 40, max_distance_km: 50)
    ProfileLocation.create!(profile: candidate, user: candidate_user, brand: @brand,
      latitude: @locality.latitude, longitude: @locality.longitude, accuracy_meters: 20, source: "device",
      captured_at: Time.current)

    get "/api/v1/find", headers: bearer_headers(@token)

    assert_response :success
    assert_equal [ candidate.public_id ], JSON.parse(response.body).fetch("profiles").map { |p| p.fetch("id") }
  end

  private

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end
end
