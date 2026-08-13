require "test_helper"

class Api::V1::DiscoveryControllerTest < ActionDispatch::IntegrationTest
  setup do
    @brand = Brand.create!(slug: "hookus", name: "HookUs")
    BrandDomain.create!(brand: @brand, host: "hookus.test")
    @viewer = create_profile(
      brand: @brand, gender: "woman", age: 30,
      interested_in: [ "man" ], min_age: 25, max_age: 40
    )
    @token, = Session.issue!(brand: @brand, user: @viewer.user)
    host! "hookus.test"
  end

  test "requires authentication" do
    get "/api/v1/discovery"

    assert_response :unauthorized
  end

  test "requires an active visible viewer with complete matching preferences" do
    @viewer.update!(status: :draft)

    get "/api/v1/discovery", headers: bearer_headers(@token)

    assert_response :forbidden
    assert_equal({ "error" => "discoverable_profile_required" }, JSON.parse(response.body))
  end

  test "returns public same-brand profiles without private identifiers or coordinates" do
    Profiles::HookusProfileCatalog.install!(brand: @brand)
    candidate = create_candidate(display_name: "Sam")
    Profiles::OptionSelections.replace!(profile: candidate, selections: { intents: [ "hookups" ], vibes: [ "chill" ] })
    create_location(candidate)

    get "/api/v1/discovery", headers: bearer_headers(@token)

    assert_response :success
    profile = JSON.parse(response.body).fetch("profiles").sole
    assert_equal candidate.public_id, profile.fetch("id")
    assert_equal "Sam", profile.fetch("display_name")
    assert_equal [ "hookups" ], profile.fetch("options").fetch("intents")
    assert_not_equal candidate.id.to_s, profile.fetch("id")
    assert_not profile.key?("birthdate")
    assert_not profile.key?("user_id")
    assert_not profile.key?("latitude")
    assert_not profile.key?("longitude")
    assert_not_includes response.body, "-33.9249"
    assert_not_includes response.body, "18.4241"
  end

  test "paginates deterministically with a signed brand-bound cursor" do
    candidates = 3.times.map { |index| create_candidate(display_name: "Candidate #{index}") }
    candidates.each_with_index do |candidate, index|
      candidate.update_columns(created_at: Time.utc(2026, 8, 13, 12, 0, index), updated_at: Time.current)
    end

    get "/api/v1/discovery", headers: bearer_headers(@token), params: { limit: 2 }

    assert_response :success
    first_page = JSON.parse(response.body)
    assert_equal [ candidates[2].public_id, candidates[1].public_id ], first_page.fetch("profiles").pluck("id")
    assert first_page.fetch("next_cursor").present?

    get "/api/v1/discovery",
      headers: bearer_headers(@token),
      params: { limit: 2, cursor: first_page.fetch("next_cursor") }

    assert_response :success
    second_page = JSON.parse(response.body)
    assert_equal [ candidates[0].public_id ], second_page.fetch("profiles").pluck("id")
    assert_nil second_page.fetch("next_cursor")
  end

  test "rejects tampered cursors and invalid limits" do
    get "/api/v1/discovery", headers: bearer_headers(@token), params: { cursor: "not-a-cursor" }

    assert_response :unprocessable_entity
    assert_equal "invalid_cursor", JSON.parse(response.body).fetch("error")

    get "/api/v1/discovery", headers: bearer_headers(@token), params: { limit: 51 }

    assert_response :unprocessable_entity
    assert_equal "invalid_limit", JSON.parse(response.body).fetch("error")
  end

  test "does not accept a cursor for another brand" do
    candidate = create_candidate
    cursor = Matching::Cursor.encode(
      brand: @brand,
      strategy: Matching::Strategies::Hookus,
      profile: candidate
    )
    other_brand = Brand.create!(slug: "other-hookus", name: "Other HookUs")

    assert_raises Matching::Cursor::Invalid do
      Matching::Cursor.apply(
        scope: other_brand.profiles,
        value: cursor,
        brand: other_brand,
        strategy: Matching::Strategies::Hookus
      )
    end
  end

  test "returns not found when matching is not configured for the brand" do
    unsupported_brand = Brand.create!(slug: "future-brand", name: "Future Brand")
    BrandDomain.create!(brand: unsupported_brand, host: "future.test")
    unsupported_viewer = create_profile(
      brand: unsupported_brand, gender: "woman", age: 30,
      interested_in: [ "man" ], min_age: 25, max_age: 40
    )
    token, = Session.issue!(brand: unsupported_brand, user: unsupported_viewer.user)
    host! "future.test"

    get "/api/v1/discovery", headers: bearer_headers(token)

    assert_response :not_found
    assert_equal "matching_not_configured", JSON.parse(response.body).fetch("error")
  end

  test "preloads public options with bounded select queries" do
    Profiles::HookusProfileCatalog.install!(brand: @brand)
    5.times do
      candidate = create_candidate
      Profiles::OptionSelections.replace!(profile: candidate, selections: { intents: [ "hookups" ], vibes: [ "chill" ] })
    end

    select_count = count_select_queries do
      get "/api/v1/discovery", headers: bearer_headers(@token)
    end

    assert_response :success
    assert_operator select_count, :<=, 12
    assert_equal 5, JSON.parse(response.body).fetch("profiles").size
  end

  private

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end

  def create_candidate(display_name: nil)
    create_profile(
      brand: @brand, gender: "man", age: 30, interested_in: [ "woman" ],
      min_age: 25, max_age: 40, display_name:
    )
  end

  def create_profile(brand:, gender:, age:, interested_in:, min_age:, max_age:, display_name: nil)
    user = User.create!
    membership = BrandMembership.create!(brand:, user:)
    profile = Profile.create!(
      brand:, user:, brand_membership: membership, display_name:, gender:,
      birthdate: age.years.ago.to_date, status: :active, visibility: :visible
    )
    ProfilePreference.create!(brand:, user:, profile:, interested_in:, min_age:, max_age:)
    profile
  end

  def create_location(profile)
    ProfileLocation.create!(
      profile:, user: profile.user, brand: profile.brand,
      latitude: -33.9249, longitude: 18.4241, accuracy_meters: 20,
      source: "device", captured_at: Time.current
    )
  end

  def count_select_queries
    count = 0
    callback = lambda do |_name, _start, _finish, _id, payload|
      count += 1 if payload[:sql].match?(/\ASELECT/i) && payload[:name] != "SCHEMA"
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    count
  end
end
