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
    require_only_public_options
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

  test "ranks with declared HookUs capabilities and returns bounded compatibility metadata" do
    Profiles::HookusProfileCatalog.install!(brand: @brand)
    require_only_public_options
    select_options(@viewer, intents: %w[hookups casual], vibes: %w[chill music])
    create_location(@viewer)
    strongest = create_candidate(display_name: "Strongest")
    select_options(strongest, intents: %w[hookups casual], vibes: %w[chill music])
    create_location(strongest)
    weaker = create_candidate(display_name: "Weaker")
    select_options(weaker, intents: %w[relationship], vibes: %w[gaming])

    get "/api/v1/discovery", headers: bearer_headers(@token)

    assert_response :success
    profiles = JSON.parse(response.body).fetch("profiles")
    assert_equal [ strongest.public_id, weaker.public_id ], profiles.pluck("id")
    assert_equal({
      "score" => 100,
      "confidence" => 0.75,
      "reasons" => %w[shared_intent similar_vibe mutual_age_fit]
    }, profiles.first.fetch("compatibility"))
    assert_equal 19, profiles.last.dig("compatibility", "score")
    assert_equal 0.75, profiles.last.dig("compatibility", "confidence")
    assert_equal [ "mutual_age_fit" ], profiles.last.dig("compatibility", "reasons")
  end

  test "uses distance only when either profile configured a distance preference" do
    candidate = create_candidate
    create_location(@viewer)
    create_location(candidate)

    get "/api/v1/discovery", headers: bearer_headers(@token)

    without_preference = JSON.parse(response.body).fetch("profiles").sole.fetch("compatibility")
    assert_equal 0.25, without_preference.fetch("confidence")
    assert_not_includes without_preference.fetch("reasons"), "nearby"

    candidate.profile_preference.update!(max_distance_km: 50)
    get "/api/v1/discovery", headers: bearer_headers(@token)

    with_preference = JSON.parse(response.body).fetch("profiles").sole.fetch("compatibility")
    assert_equal 0.5, with_preference.fetch("confidence")
    assert_not_includes with_preference.fetch("reasons"), "nearby"
    assert_not_includes response.body, "nearby"
  end

  test "does not use owner-only option groups in score reasons" do
    Profiles::HookusProfileCatalog.install!(brand: @brand)
    require_only_public_options
    select_options(@viewer, intents: [ "hookups" ], vibes: [ "chill" ])
    candidate = create_candidate
    select_options(candidate, intents: [ "hookups" ], vibes: [ "chill" ])
    private_group = ProfileOptionGroup.create!(
      brand: @brand, key: "private_preference", label: "Private preference",
      cardinality: :single, max_selections: 1, visibility: :owner_only
    )
    private_option = ProfileOption.create!(
      brand: @brand, profile_option_group: private_group, code: "secret_value", label: "Secret value"
    )
    [ @viewer, candidate ].each do |profile|
      ProfileOptionSelection.create!(
        profile:, user: profile.user, brand: @brand,
        profile_option_group: private_group, profile_option: private_option
      )
    end

    get "/api/v1/discovery", headers: bearer_headers(@token)

    assert_response :success
    payload = JSON.parse(response.body).fetch("profiles").sole
    assert_not payload.fetch("options").key?("private_preference")
    assert_not_includes payload.dig("compatibility", "reasons"), "secret_value"
    assert_not_includes response.body, "Secret value"
  end

  test "paginates across score boundaries without duplicates" do
    Profiles::HookusProfileCatalog.install!(brand: @brand)
    require_only_public_options
    select_options(@viewer, intents: %w[hookups casual], vibes: %w[chill music])
    strongest = create_candidate
    select_options(strongest, intents: %w[hookups casual], vibes: %w[chill music])
    middle = create_candidate
    select_options(middle, intents: %w[hookups relationship], vibes: [ "gaming" ])
    weakest = create_candidate
    select_options(weakest, intents: [ "relationship" ], vibes: [ "gaming" ])

    ids = []
    cursor = nil
    3.times do
      get "/api/v1/discovery", headers: bearer_headers(@token), params: { limit: 1, cursor: }.compact
      assert_response :success
      page = JSON.parse(response.body)
      ids << page.fetch("profiles").sole.fetch("id")
      cursor = page.fetch("next_cursor")
    end

    assert_equal [ strongest.public_id, middle.public_id, weakest.public_id ], ids
    assert_nil cursor
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
    ranked_candidate = Matching::Strategies::Hookus.rank(
      scope: @brand.profiles.where(id: candidate.id), viewer: @viewer
    ).first
    cursor = Matching::Cursor.encode(
      brand: @brand,
      strategy: Matching::Strategies::Hookus,
      profile: ranked_candidate
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

  test "does not expose the Date9ja contract strategy as production discovery" do
    date9ja = Brand.create!(slug: "date9ja", name: "Date9ja")
    BrandDomain.create!(brand: date9ja, host: "date9ja.test")
    viewer = create_profile(
      brand: date9ja, gender: "woman", age: 30,
      interested_in: [ "man" ], min_age: 25, max_age: 40
    )
    token, = Session.issue!(brand: date9ja, user: viewer.user)
    host! "date9ja.test"

    get "/api/v1/discovery", headers: bearer_headers(token)

    assert_response :not_found
    assert_equal "matching_not_configured", JSON.parse(response.body).fetch("error")
  end

  test "preloads public options with bounded select queries" do
    Profiles::HookusProfileCatalog.install!(brand: @brand)
    require_only_public_options
    candidate = create_candidate
    Profiles::OptionSelections.replace!(profile: candidate, selections: { intents: [ "hookups" ], vibes: [ "chill" ] })

    baseline_count = count_select_queries do
      get "/api/v1/discovery", headers: bearer_headers(@token)
    end

    4.times do
      additional = create_candidate
      Profiles::OptionSelections.replace!(profile: additional, selections: { intents: [ "hookups" ], vibes: [ "chill" ] })
    end

    select_count = count_select_queries do
      get "/api/v1/discovery", headers: bearer_headers(@token)
    end

    assert_response :success
    assert_operator select_count, :<=, baseline_count + 1
    assert_equal 5, JSON.parse(response.body).fetch("profiles").size
  end

  test "excludes profiles with an existing like pass or match" do
    liked = create_candidate
    passed = create_candidate
    matched = create_candidate
    Like.create!(brand: @brand, liker_profile: @viewer, liked_profile: liked)
    ProfilePass.create!(brand: @brand, passer_profile: @viewer, passed_profile: passed)
    profile_a_id, profile_b_id = Match.canonical_pair(@viewer.id, matched.id)
    Match.create!(brand: @brand, profile_a_id:, profile_b_id:)

    get "/api/v1/discovery", headers: bearer_headers(@token)

    assert_response :success
    assert_empty JSON.parse(response.body).fetch("profiles")
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

  def select_options(profile, **selections)
    Profiles::OptionSelections.replace!(profile:, selections:)
  end

  def count_select_queries
    count = 0
    callback = lambda do |_name, _start, _finish, _id, payload|
      count += 1 if payload[:sql].match?(/\ASELECT/i) && payload[:name] != "SCHEMA"
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    count
  end

  def require_only_public_options
    @brand.update!(profile_requirements: {
      profile_fields: [],
      preference_fields: [],
      collections: [],
      option_groups: %w[ intents vibes ]
    })
  end
end
