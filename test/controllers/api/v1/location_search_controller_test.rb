require "test_helper"

class Api::V1::LocationSearchControllerTest < ActionDispatch::IntegrationTest
  setup do
    @brand = Brand.create!(slug: "dateza", name: "DateZA")
    Profiles::DatezaProfileCatalog.install!(brand: @brand)
    BrandDomain.create!(brand: @brand, host: "dateza.test")
    Geography::SouthAfricaCatalog.install!
    other_country = Place.create!(kind: :country, code: "gb", name: "United Kingdom", country_code: "GB",
      latitude: 0, longitude: 0)
    @foreign_region = Place.create!(kind: :region, parent: other_country, code: "london", name: "London",
      country_code: "GB", latitude: 51.5, longitude: -0.1)
    @viewer = create_profile(brand: @brand)
    @token, = Session.issue!(brand: @brand, user: @viewer.user)
    host! "dateza.test"
  end

  test "requires authentication" do
    get "/api/v1/locations/search", params: { q: "sea point" }

    assert_response :unauthorized
  end

  test "returns normalized ZA results for a suburb query" do
    get "/api/v1/locations/search", headers: bearer_headers(@token), params: { q: "sea po" }

    assert_response :success
    results = JSON.parse(response.body).fetch("results")
    entry = results.sole
    assert_equal Place.kept.find_by!(code: "sea-point").id, entry.fetch("place_id")
    assert_equal "Sea Point, Cape Town, Western Cape", entry.fetch("label")
    assert_equal "Sea Point", entry.fetch("area")
    assert_equal "Cape Town", entry.fetch("city")
    assert_equal "Western Cape", entry.fetch("region")
    assert_equal "ZA", entry.fetch("country_code")
    assert_equal "locality", entry.fetch("kind")
  end

  test "returns a locality-level result nested under its city and region" do
    get "/api/v1/locations/search", headers: bearer_headers(@token), params: { q: "sandton" }

    assert_response :success
    entry = JSON.parse(response.body).fetch("results").sole
    assert_equal "locality", entry.fetch("kind")
    assert_equal "Sandton", entry.fetch("area")
    assert_equal "Johannesburg", entry.fetch("city")
    assert_equal "Gauteng", entry.fetch("region")
  end

  test "returns a city-level result whose own name is both area and city" do
    get "/api/v1/locations/search", headers: bearer_headers(@token), params: { q: "johannesburg" }

    assert_response :success
    entry = JSON.parse(response.body).fetch("results").sole
    assert_equal "city", entry.fetch("kind")
    assert_equal "Johannesburg", entry.fetch("area")
    assert_equal "Johannesburg", entry.fetch("city")
    assert_equal "Gauteng", entry.fetch("region")
  end

  test "never returns results outside the brand's configured countries" do
    get "/api/v1/locations/search", headers: bearer_headers(@token), params: { q: "london" }

    assert_response :success
    assert_empty JSON.parse(response.body).fetch("results")
  end

  test "never returns a country-level result even when the country's own name also matches" do
    # "South Africa" (kind: country) and the seeded "Outside South Africa"
    # fallback (kind: region) both contain this substring — only the region
    # is an acceptable result.
    get "/api/v1/locations/search", headers: bearer_headers(@token), params: { q: "south africa" }

    assert_response :success
    results = JSON.parse(response.body).fetch("results")
    assert results.any?, "expected the 'Outside South Africa' region to still match"
    assert results.none? { |entry| entry.fetch("kind") == "country" }
  end

  test "rejects a blank query" do
    get "/api/v1/locations/search", headers: bearer_headers(@token), params: { q: "" }

    assert_response :unprocessable_entity
    assert_equal "query_too_short", JSON.parse(response.body).fetch("error")
  end

  test "rejects a query below the minimum length" do
    get "/api/v1/locations/search", headers: bearer_headers(@token), params: { q: "s" }

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_equal "query_too_short", body.fetch("error")
    assert_equal 2, body.fetch("min_length")
  end

  test "rejects a missing query" do
    get "/api/v1/locations/search", headers: bearer_headers(@token)

    assert_response :unprocessable_entity
  end

  test "normalizes surrounding and repeated whitespace" do
    get "/api/v1/locations/search", headers: bearer_headers(@token), params: { q: "  sea   point  " }

    assert_response :success
    assert_equal [ "Sea Point" ], JSON.parse(response.body).fetch("results").map { |r| r.fetch("area") }
  end

  test "escapes SQL LIKE wildcard characters instead of matching everything" do
    get "/api/v1/locations/search", headers: bearer_headers(@token), params: { q: "a%" }

    assert_response :success
    assert_empty JSON.parse(response.body).fetch("results"),
      "an unescaped '%' would match nearly every place name containing 'a'"
  end

  test "limits results and never exceeds the documented maximum" do
    12.times do |i|
      Place.create!(
        kind: :locality, parent: Place.kept.find_by!(code: "cape-town"),
        code: "test-suburb-#{i}", name: "Test Suburb #{i}", country_code: "ZA",
        latitude: -33.9, longitude: 18.4
      )
    end

    get "/api/v1/locations/search", headers: bearer_headers(@token), params: { q: "test suburb" }

    assert_response :success
    results = JSON.parse(response.body).fetch("results")
    assert_operator results.size, :<=, Geography::Search::MAX_RESULTS
  end

  test "a search result's place_id is directly usable by PUT /profile/place" do
    get "/api/v1/locations/search", headers: bearer_headers(@token), params: { q: "sea point" }
    place_id = JSON.parse(response.body).fetch("results").sole.fetch("place_id")

    put "/api/v1/profile/place", headers: bearer_headers(@token), params: { place_id: }

    assert_response :success
    location = JSON.parse(response.body).fetch("location")
    assert_equal "Sea Point, Cape Town, Western Cape", location.dig("place", "display_path")
  end

  test "is not configured for a brand without the place_selection capability" do
    hookus = Brand.create!(slug: "hookus", name: "HookUs")
    BrandDomain.create!(brand: hookus, host: "hookus.test")
    hookus_viewer = create_profile(brand: hookus)
    hookus_token, = Session.issue!(brand: hookus, user: hookus_viewer.user)
    host! "hookus.test"

    get "/api/v1/locations/search", headers: bearer_headers(hookus_token), params: { q: "sandton" }

    assert_response :not_found
    assert_equal "capability_not_configured", JSON.parse(response.body).fetch("error")
  end

  test "excessive requests are rate limited" do
    AbuseProtection::Policy::RULES.fetch(:location_search).find { |rule| rule.name == "burst" }.limit.times do
      get "/api/v1/locations/search", headers: bearer_headers(@token), params: { q: "sea point" }
      assert_response :success
    end

    get "/api/v1/locations/search", headers: bearer_headers(@token), params: { q: "sea point" }

    assert_response :too_many_requests
  end

  test "repeated equivalent queries use the cache instead of re-querying the provider" do
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    call_count = 0

    stub_method(Geography::PlaceCatalogProvider, :search, ->(query:, country_codes:) { call_count += 1; [] }) do
      Geography::Search.call(brand: @brand, query: "Sea Point")
      Geography::Search.call(brand: @brand, query: "sea point")
      Geography::Search.call(brand: @brand, query: "  sea point  ")
    end

    assert_equal 1, call_count
  ensure
    Rails.cache = original_cache
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
