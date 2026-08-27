require "test_helper"

class Api::V1::ProfileLocationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @brand = Brand.create!(slug: "hookus", name: "HookUs")
    BrandDomain.create!(brand: @brand, host: "hookus.test")
    @user = User.create!
    @membership = BrandMembership.create!(brand: @brand, user: @user)
    @profile = Profile.create!(brand: @brand, user: @user, brand_membership: @membership)
    @token, = Session.issue!(brand: @brand, user: @user)
    host! "hookus.test"
  end

  test "requires authentication" do
    put "/api/v1/profile/location", params: valid_params

    assert_response :unauthorized
  end

  test "GET requires authentication" do
    get "/api/v1/profile/location"

    assert_response :unauthorized
  end

  test "GET reports unconfigured when there is no profile" do
    @profile.destroy!

    get "/api/v1/profile/location", headers: bearer_headers(@token)

    assert_response :success
    assert_equal({ "location" => { "configured" => false } }, JSON.parse(response.body))
  end

  test "GET reports unconfigured when a profile exists with no location" do
    get "/api/v1/profile/location", headers: bearer_headers(@token)

    assert_response :success
    assert_equal({ "location" => { "configured" => false } }, JSON.parse(response.body))
  end

  test "GET reflects a raw-coordinate location without exposing coordinates or internal ids" do
    create_location

    get "/api/v1/profile/location", headers: bearer_headers(@token)

    assert_response :success
    body = JSON.parse(response.body).fetch("location")
    assert_equal true, body.fetch("configured")
    assert_equal "device", body.fetch("source")
    assert_equal 25, body.fetch("accuracy_meters")
    assert_nil body.fetch("place")
    assert_not body.key?("latitude")
    assert_not body.key?("longitude")
    assert_not_includes response.body, "-33.9248685"
    assert_not_includes response.body, "18.4240553"
    assert_equal %w[accuracy_meters captured_at configured place source], body.keys.sort
  end

  test "GET immediately reflects a fresh raw-coordinate update" do
    put "/api/v1/profile/location", headers: bearer_headers(@token), params: valid_params

    get "/api/v1/profile/location", headers: bearer_headers(@token)
    assert_equal 25, JSON.parse(response.body).dig("location", "accuracy_meters")

    put "/api/v1/profile/location", headers: bearer_headers(@token),
      params: valid_params.merge(accuracy_meters: 5000)

    get "/api/v1/profile/location", headers: bearer_headers(@token)
    assert_equal 5000, JSON.parse(response.body).dig("location", "accuracy_meters")
  end

  test "GET reports unconfigured again after the location is soft deleted" do
    create_location

    delete "/api/v1/profile/location", headers: bearer_headers(@token)
    assert_response :success

    get "/api/v1/profile/location", headers: bearer_headers(@token)

    assert_response :success
    assert_equal false, JSON.parse(response.body).dig("location", "configured")
  end

  test "GET never exposes another brand's location for the same user" do
    other_brand = Brand.create!(slug: "date9ja", name: "Date9ja")
    other_membership = BrandMembership.create!(brand: other_brand, user: @user)
    other_profile = Profile.create!(brand: other_brand, user: @user, brand_membership: other_membership)
    create_location(brand: other_brand, profile: other_profile)

    get "/api/v1/profile/location", headers: bearer_headers(@token)

    assert_response :success
    assert_equal false, JSON.parse(response.body).dig("location", "configured")
  end

  test "GET query parameters cannot select another member's location" do
    create_location

    other_user = User.create!
    other_membership = BrandMembership.create!(brand: @brand, user: other_user)
    other_profile = Profile.create!(brand: @brand, user: other_user, brand_membership: other_membership)
    create_location(profile: other_profile, user: other_user)

    get "/api/v1/profile/location?profile_id=#{other_profile.public_id}", headers: bearer_headers(@token)

    assert_response :success
    location = ProfileLocation.kept.find_by(profile: @profile)
    assert_equal location.accuracy_meters, JSON.parse(response.body).dig("location", "accuracy_meters")
  end

  test "a suspended profile can still read its own configured location" do
    create_location
    @profile.update!(status: :suspended)

    get "/api/v1/profile/location", headers: bearer_headers(@token)

    assert_response :success
    assert_equal true, JSON.parse(response.body).dig("location", "configured")
  end

  test "GET agrees with the /profile summary's configured boolean" do
    get "/api/v1/profile/location", headers: bearer_headers(@token)
    get "/api/v1/profile", headers: bearer_headers(@token)
    assert_equal false, JSON.parse(response.body).dig("profile", "location", "configured")

    create_location

    get "/api/v1/profile/location", headers: bearer_headers(@token)
    detailed = JSON.parse(response.body).dig("location", "configured")

    get "/api/v1/profile", headers: bearer_headers(@token)
    summary = JSON.parse(response.body).dig("profile", "location", "configured")

    assert_equal true, detailed
    assert_equal detailed, summary
  end

  test "switching from a place-selected location to a raw-coordinate one clears the stale place" do
    country = Place.create!(kind: :country, code: "za-t", name: "South Africa", country_code: "ZA",
      latitude: 0, longitude: 0)
    region = Place.create!(kind: :region, parent: country, code: "wc-t", name: "Western Cape",
      country_code: "ZA", latitude: -33.0, longitude: 19.0)
    city = Place.create!(kind: :city, parent: region, code: "cpt-t", name: "Cape Town",
      country_code: "ZA", latitude: -33.9, longitude: 18.4)
    location = create_location
    location.update!(source: "place", place: city)

    put "/api/v1/profile/location", headers: bearer_headers(@token), params: valid_params

    assert_response :success
    assert_nil location.reload.place_id
    assert_equal "device", location.source

    get "/api/v1/profile/location", headers: bearer_headers(@token)
    assert_nil JSON.parse(response.body).dig("location", "place")
  end

  test "stores private coordinates without returning them" do
    assert_difference -> { ProfileLocation.count }, 1 do
      put "/api/v1/profile/location",
        headers: bearer_headers(@token),
        params: valid_params.merge(source: "imported")
    end

    assert_response :success
    location = ProfileLocation.last
    payload = JSON.parse(response.body).fetch("location")

    assert_equal @brand, location.brand
    assert_equal @user, location.user
    assert_equal @profile, location.profile
    assert_equal BigDecimal("-33.9248685"), location.latitude
    assert_equal BigDecimal("18.4240553"), location.longitude
    assert_equal "device", location.source
    assert_equal true, payload.fetch("configured")
    assert_equal 25, payload.fetch("accuracy_meters")
    assert_not payload.key?("latitude")
    assert_not payload.key?("longitude")
    assert_not_includes response.body, "-33.9248685"
    assert_not_includes response.body, "18.4240553"
  end

  test "updates the active location instead of creating another" do
    location = create_location

    assert_no_difference -> { ProfileLocation.count } do
      put "/api/v1/profile/location",
        headers: bearer_headers(@token),
        params: valid_params.merge(latitude: -34.0, longitude: 18.5, accuracy_meters: 50)
    end

    assert_response :success
    assert_equal BigDecimal("-34.0"), location.reload.latitude
    assert_equal BigDecimal("18.5"), location.longitude
    assert_equal 50, location.accuracy_meters
  end

  test "requires a current brand profile" do
    @profile.destroy!

    put "/api/v1/profile/location", headers: bearer_headers(@token), params: valid_params

    assert_response :forbidden
    assert_equal({ "error" => "profile_required" }, JSON.parse(response.body))
  end

  test "rejects invalid coordinates and future capture times" do
    put "/api/v1/profile/location",
      headers: bearer_headers(@token),
      params: valid_params.merge(latitude: -91, captured_at: 10.minutes.from_now.iso8601)

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_equal "invalid_location", body.fetch("error")
    assert body.fetch("details").fetch("latitude").present?
    assert body.fetch("details").fetch("captured_at").present?
  end

  test "does not replace another brand location for the same user" do
    other_brand = Brand.create!(slug: "date9ja", name: "Date9ja")
    other_membership = BrandMembership.create!(brand: other_brand, user: @user)
    other_profile = Profile.create!(brand: other_brand, user: @user, brand_membership: other_membership)
    other_location = create_location(brand: other_brand, profile: other_profile)

    put "/api/v1/profile/location", headers: bearer_headers(@token), params: valid_params

    assert_response :success
    assert_equal 2, ProfileLocation.count
    assert_equal BigDecimal("-33.9248685"), other_location.reload.latitude
    assert_equal @brand, ProfileLocation.order(:id).last.brand
  end

  test "soft deletes the current location and is idempotent" do
    location = create_location

    delete "/api/v1/profile/location", headers: bearer_headers(@token)

    assert_response :success
    assert location.reload.deleted_at.present?
    assert_equal({ "location" => { "configured" => false } }, JSON.parse(response.body))

    assert_no_changes -> { location.reload.deleted_at } do
      delete "/api/v1/profile/location", headers: bearer_headers(@token)
    end
    assert_response :success
  end

  test "snaps raw device coordinates to coarse precision for a place-selection brand" do
    dateza = Brand.create!(slug: "dateza", name: "DateZA")
    Profiles::DatezaProfileCatalog.install!(brand: dateza)
    BrandDomain.create!(brand: dateza, host: "dateza-loc.test")
    user = User.create!
    membership = BrandMembership.create!(brand: dateza, user:)
    Profile.create!(brand: dateza, user:, brand_membership: membership)
    token, = Session.issue!(brand: dateza, user:)
    host! "dateza-loc.test"

    put "/api/v1/profile/location", headers: bearer_headers(token),
      params: valid_params.merge(accuracy_meters: 10)

    assert_response :success
    location = ProfileLocation.order(:id).last
    assert_equal BigDecimal("-33.92"), location.latitude
    assert_equal BigDecimal("18.42"), location.longitude
    assert_equal Profiles::CurrentPlace::ACCURACY_METERS_BY_KIND.fetch("locality"), location.accuracy_meters
  end

  test "does not soften a place-selection brand's already-coarse reported accuracy" do
    dateza = Brand.create!(slug: "dateza", name: "DateZA")
    Profiles::DatezaProfileCatalog.install!(brand: dateza)
    BrandDomain.create!(brand: dateza, host: "dateza-loc2.test")
    user = User.create!
    membership = BrandMembership.create!(brand: dateza, user:)
    Profile.create!(brand: dateza, user:, brand_membership: membership)
    token, = Session.issue!(brand: dateza, user:)
    host! "dateza-loc2.test"

    put "/api/v1/profile/location", headers: bearer_headers(token),
      params: valid_params.merge(accuracy_meters: 50_000)

    assert_response :success
    assert_equal 50_000, ProfileLocation.order(:id).last.accuracy_meters
  end

  private

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end

  def valid_params
    {
      latitude: -33.9248685,
      longitude: 18.4240553,
      accuracy_meters: 25,
      captured_at: Time.current.iso8601
    }
  end

  def create_location(brand: @brand, profile: @profile, user: @user)
    ProfileLocation.create!(
      brand:, user:, profile:, latitude: -33.9248685, longitude: 18.4240553,
      accuracy_meters: 25, source: "device", captured_at: Time.current
    )
  end
end
