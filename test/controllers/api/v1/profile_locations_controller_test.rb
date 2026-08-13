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

  def create_location(brand: @brand, profile: @profile)
    ProfileLocation.create!(
      brand:, user: @user, profile:, latitude: -33.9248685, longitude: 18.4240553,
      accuracy_meters: 25, source: "device", captured_at: Time.current
    )
  end
end
