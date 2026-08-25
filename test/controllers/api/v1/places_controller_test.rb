require "test_helper"

class Api::V1::PlacesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @brand = Brand.create!(slug: "dateza", name: "DateZA")
    Profiles::DatezaProfileCatalog.install!(brand: @brand)
    BrandDomain.create!(brand: @brand, host: "dateza.test")
    Geography::SouthAfricaCatalog.install!
    other_country = Place.create!(kind: :country, code: "na", name: "Namibia", country_code: "NA",
      latitude: 0, longitude: 0)
    @foreign_region = Place.create!(kind: :region, parent: other_country, code: "khomas", name: "Khomas",
      country_code: "NA", latitude: -22.5, longitude: 17.0)
    @viewer = create_profile(brand: @brand)
    @token, = Session.issue!(brand: @brand, user: @viewer.user)
    host! "dateza.test"
  end

  test "requires authentication" do
    get "/api/v1/places"
    assert_response :unauthorized
  end

  test "lists only DateZA's supported country's top-level regions with no parent_id" do
    get "/api/v1/places", headers: bearer_headers(@token)

    assert_response :success
    places = JSON.parse(response.body).fetch("places")
    assert_equal Geography::SouthAfricaCatalog::REGIONS.size + 1, places.size
    assert(places.all? { |p| p.fetch("kind") == "region" })
    codes = places.map { |p| p.fetch("code") }
    assert_not_includes codes, @foreign_region.code
    assert_includes codes, Geography::SouthAfricaCatalog::OUTSIDE_COUNTRY_FALLBACK.fetch(:code)
  end

  test "lists children of a given parent_id" do
    western_cape = Place.kept.find_by!(code: "western-cape")

    get "/api/v1/places", headers: bearer_headers(@token), params: { parent_id: western_cape.id }

    assert_response :success
    places = JSON.parse(response.body).fetch("places")
    assert_equal [ "cape-town" ], places.map { |p| p.fetch("code") }
    assert_equal true, places.first.fetch("has_children")
  end

  test "rejects a parent_id belonging to an unsupported country" do
    get "/api/v1/places", headers: bearer_headers(@token), params: { parent_id: @foreign_region.id }

    assert_response :not_found
    assert_equal({ "error" => "place_not_found" }, JSON.parse(response.body))
  end

  test "rejects an unknown parent_id" do
    get "/api/v1/places", headers: bearer_headers(@token), params: { parent_id: -1 }

    assert_response :not_found
  end

  test "is not configured for a brand without the place_selection capability" do
    hookus = Brand.create!(slug: "hookus", name: "HookUs")
    BrandDomain.create!(brand: hookus, host: "hookus.test")
    hookus_viewer = create_profile(brand: hookus)
    hookus_token, = Session.issue!(brand: hookus, user: hookus_viewer.user)
    host! "hookus.test"

    get "/api/v1/places", headers: bearer_headers(hookus_token)

    assert_response :not_found
    assert_equal "capability_not_configured", JSON.parse(response.body).fetch("error")
  end

  private

  def create_profile(brand:)
    user = User.create!
    membership = BrandMembership.create!(brand:, user:)
    Profile.create!(brand:, user:, brand_membership: membership, gender: "woman",
      birthdate: 30.years.ago.to_date, status: :active, visibility: :visible)
  end

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end
end
