require "test_helper"

class Api::V1::FindControllerTest < ActionDispatch::IntegrationTest
  setup do
    @brand = Brand.create!(slug: "dateza", name: "DateZA")
    Profiles::DatezaProfileCatalog.install!(brand: @brand)
    BrandDomain.create!(brand: @brand, host: "dateza.test")
    @viewer = create_profile(
      brand: @brand, gender: "woman", age: 30, interested_in: [ "man" ],
      min_age: 18, max_age: 60, max_distance_km: 100
    )
    create_location(@viewer, latitude: -26.2041, longitude: 28.0473)
    identifier = IdentityIdentifier.create!(
      user: @viewer.user, kind: :email, normalized_value: "find-viewer@example.com", verified_at: Time.current
    )
    credential = Credential.create!(user: @viewer.user, identity_identifier: identifier, kind: :password)
    @token, = Session.issue!(brand: @brand, user: @viewer.user, credential:)
    host! "dateza.test"
  end

  test "requires authentication and a registered Find brand" do
    get "/api/v1/find"
    assert_response :unauthorized

    hookus = Brand.create!(slug: "hookus", name: "HookUs")
    BrandDomain.create!(brand: hookus, host: "hookus.test")
    hookus_viewer = create_profile(
      brand: hookus, gender: "woman", age: 30, interested_in: [ "man" ], min_age: 18, max_age: 60
    )
    hookus_token, = Session.issue!(brand: hookus, user: hookus_viewer.user)
    host! "hookus.test"

    get "/api/v1/find", headers: bearer_headers(hookus_token)

    assert_response :not_found
    assert_equal({ "error" => "find_not_configured" }, JSON.parse(response.body))

    host! "dateza.test"
    get "/api/v1/find", headers: bearer_headers(hookus_token)
    assert_response :unauthorized
  end

  test "translates the shared discoverable-viewer rejection to the Find API error" do
    @viewer.update!(visibility: :hidden)

    get "/api/v1/find", headers: bearer_headers(@token)

    assert_response :forbidden
    assert_equal({ "error" => "discoverable_profile_required" }, JSON.parse(response.body))
  end

  test "DateZA profile detail does not expose HookUs capability state" do
    candidate = create_candidate

    get "/api/v1/profiles/#{candidate.public_id}", headers: bearer_headers(@token)

    assert_response :success
    profile = JSON.parse(response.body).fetch("profile")
    assert_not profile.key?("hook_state")
    assert_not profile.key?("hook_tonight_active")
  end

  test "applies shared lifecycle reciprocal age distance block and brand eligibility" do
    eligible = create_candidate
    create_candidate(profile_attributes: { visibility: :hidden })
    create_candidate(profile_attributes: { status: :draft })
    create_candidate(membership_status: :suspended)
    create_candidate(membership_status: :left)
    create_candidate(user_status: :suspended)
    create_candidate(gender: "person")
    create_candidate(interested_in: [ "man" ])
    create_candidate(age: 61)
    create_candidate(min_age: 31)
    blocked = create_candidate
    ProfileBlock.create!(brand: @brand, blocker_profile: @viewer, blocked_profile: blocked)
    far = create_candidate
    far.profile_locations.first.update!(latitude: -33.9249, longitude: 18.4241)
    other_brand = Brand.create!(slug: "other", name: "Other")
    create_profile(
      brand: other_brand, gender: "man", age: 30, interested_in: [ "woman" ], min_age: 18, max_age: 60
    )

    get "/api/v1/find", headers: bearer_headers(@token)

    assert_response :success
    assert_equal [ eligible.public_id ], JSON.parse(response.body).fetch("profiles").pluck("id")
  end

  test "surfaces at most ten unique candidates and reload does not charge again" do
    candidates = 11.times.map { |index| create_candidate(created_at: Time.utc(2026, 8, 21, 12, 0, index)) }

    get "/api/v1/find", headers: bearer_headers(@token)
    first = JSON.parse(response.body)

    assert_response :success
    assert_equal 10, first.fetch("profiles").size
    assert_equal 10, first.dig("allowance", "used")
    assert_equal 0, first.dig("allowance", "remaining")
    assert first.dig("allowance", "exhausted")
    assert_nil first.fetch("next_cursor")
    assert_not_includes first.fetch("profiles").pluck("id"), candidates.first.public_id

    get "/api/v1/find", headers: bearer_headers(@token)
    reload_payload = JSON.parse(response.body)

    assert_equal first.fetch("profiles").pluck("id"), reload_payload.fetch("profiles").pluck("id")
    assert_equal 10, FindProfileExposure.where(brand: @brand, brand_membership: @viewer.brand_membership).count
  end

  test "paginates deterministically but allowance overrides further pages" do
    candidates = 11.times.map { |index| create_candidate(created_at: Time.utc(2026, 8, 21, 12, 0, index)) }
    returned_ids = []
    cursor = nil

    4.times do
      get "/api/v1/find",
        headers: bearer_headers(@token),
        params: { limit: 3, cursor: }.compact
      assert_response :success
      payload = JSON.parse(response.body)
      returned_ids.concat(payload.fetch("profiles").pluck("id"))
      cursor = payload.fetch("next_cursor")
    end

    assert_equal candidates.last(10).reverse.map(&:public_id), returned_ids
    assert_nil cursor
    assert_equal 10, FindProfileExposure.where(brand: @brand, brand_membership: @viewer.brand_membership).count
  end

  test "fewer candidates preserves unused allowance and filters remain narrowing only" do
    long_term = create_candidate(age: 28)
    select_relationship_intent(long_term, "long_term_relationship")
    create_candidate(age: 35).tap { |profile| select_relationship_intent(profile, "friendship") }

    get "/api/v1/find", headers: bearer_headers(@token), params: {
      min_age: 25, max_age: 30, max_distance_km: 20, relationship_intent: "long_term_relationship"
    }

    payload = JSON.parse(response.body)
    assert_response :success
    assert_equal [ long_term.public_id ], payload.fetch("profiles").pluck("id")
    assert_nil payload.fetch("profiles").sole.fetch("compatibility")
    assert_equal({ "limit" => 10, "used" => 1, "remaining" => 9, "exhausted" => false },
      payload.fetch("allowance").except("resets_at"))
  end

  test "existing likes passes and matches remain excluded without changing allowance" do
    liked = create_candidate
    passed = create_candidate
    matched = create_candidate
    eligible = create_candidate
    Like.create!(brand: @brand, liker_profile: @viewer, liked_profile: liked)
    ProfilePass.create!(brand: @brand, passer_profile: @viewer, passed_profile: passed)
    profile_a_id, profile_b_id = Match.canonical_pair(@viewer.id, matched.id)
    Match.create!(brand: @brand, profile_a_id:, profile_b_id:)

    get "/api/v1/find", headers: bearer_headers(@token)

    payload = JSON.parse(response.body)
    assert_equal [ eligible.public_id ], payload.fetch("profiles").pluck("id")
    assert_equal 1, payload.dig("allowance", "used")
  end

  test "detail Like and Pass do not consume Find allowance" do
    first = create_candidate
    second = create_candidate

    get "/api/v1/find", headers: bearer_headers(@token), params: { limit: 2 }
    surfaced = JSON.parse(response.body).fetch("profiles").pluck("id")
    assert_equal 2, surfaced.size

    get "/api/v1/profiles/#{first.public_id}", headers: bearer_headers(@token)
    assert_response :success
    post "/api/v1/profiles/#{first.public_id}/likes", headers: bearer_headers(@token)
    assert_response :created
    post "/api/v1/profiles/#{second.public_id}/pass", headers: bearer_headers(@token)
    assert_response :created

    assert_equal 2, FindProfileExposure.where(brand: @brand, brand_membership: @viewer.brand_membership).count
  end

  test "allowance resets at the next Johannesburg day" do
    10.times { create_candidate }

    travel_to Time.utc(2026, 8, 21, 21, 59, 0) do
      get "/api/v1/find", headers: bearer_headers(@token)
      assert_equal 10, JSON.parse(response.body).dig("allowance", "used")
    end

    travel_to Time.utc(2026, 8, 21, 22, 0, 0) do
      get "/api/v1/find", headers: bearer_headers(@token)
      payload = JSON.parse(response.body)
      assert_equal 10, payload.dig("allowance", "used")
      assert_equal "2026-08-23T00:00:00+02:00", payload.dig("allowance", "resets_at")
    end

    assert_equal 20, FindProfileExposure.where(brand: @brand, brand_membership: @viewer.brand_membership).count
  end

  test "cursor is member and filter bound" do
    3.times { create_candidate }
    get "/api/v1/find", headers: bearer_headers(@token), params: { limit: 1, min_age: 25 }
    cursor = JSON.parse(response.body).fetch("next_cursor")

    get "/api/v1/find", headers: bearer_headers(@token), params: { limit: 1, min_age: 26, cursor: }
    assert_response :unprocessable_entity
    assert_equal "invalid_cursor", JSON.parse(response.body).fetch("error")

    other_viewer = create_profile(
      brand: @brand, gender: "woman", age: 30, interested_in: [ "man" ],
      min_age: 18, max_age: 60, max_distance_km: 100
    )
    create_location(other_viewer, latitude: -26.2041, longitude: 28.0473)
    other_token, = Session.issue!(brand: @brand, user: other_viewer.user)
    get "/api/v1/find", headers: bearer_headers(other_token), params: { limit: 1, min_age: 25, cursor: }
    assert_response :unprocessable_entity
    assert_equal "invalid_cursor", JSON.parse(response.body).fetch("error")
  end

  test "response hides exact coordinates owner-only answers and other-brand profiles" do
    candidate = create_candidate
    Profiles::OptionSelections.replace!(profile: candidate, selections: {
      has_children: [ "yes" ], religion_importance: [ "very_important" ]
    })
    candidate.update!(status: :active, visibility: :visible)
    other_brand = Brand.create!(slug: "hookus", name: "HookUs")
    other = create_profile(
      brand: other_brand, gender: "man", age: 30, interested_in: [ "woman" ], min_age: 18, max_age: 60
    )

    get "/api/v1/find", headers: bearer_headers(@token)

    body = response.body
    profile = JSON.parse(body).fetch("profiles").sole
    assert_equal candidate.public_id, profile.fetch("id")
    assert_not_equal other.public_id, profile.fetch("id")
    assert_not profile.fetch("options").key?("has_children")
    assert_not profile.fetch("options").key?("religion_importance")
    assert_not profile.key?("hook_state")
    assert_not profile.key?("hook_tonight_active")
    assert_not_includes body, "-26.2041"
    assert_not_includes body, "28.0473"
  end

  test "the max_distance_km filter still applies for a candidate whose location is old" do
    candidate = create_candidate
    candidate.profile_locations.kept.first.update!(captured_at: 90.days.ago)

    get "/api/v1/find", headers: bearer_headers(@token), params: { max_distance_km: 50 }
    assert_response :success
    assert_equal [ candidate.public_id ], JSON.parse(response.body).fetch("profiles").map { |p| p.fetch("id") }
  end

  test "the max_distance_km filter still excludes candidates outside the radius" do
    candidate = create_candidate
    candidate.profile_locations.kept.first.update!(latitude: -33.9249, longitude: 18.4241, captured_at: 90.days.ago)

    get "/api/v1/find", headers: bearer_headers(@token), params: { max_distance_km: 50 }
    assert_response :success
    assert_empty JSON.parse(response.body).fetch("profiles")
  end

  test "decorates surfaced profiles with DateZA compatibility without changing exposure accounting" do
    candidate = create_candidate
    compatibility_values = {
      relationship_intent: [ "long_term_relationship" ],
      has_children: [ "no" ],
      wants_children: [ "yes" ],
      religion_importance: [ "somewhat_important" ],
      social_style: [ "ambivert" ],
      meeting_pace: [ "few_days" ]
    }
    [ @viewer, candidate ].each do |profile|
      profile.update!(smoking: "never", drinking: "occasionally")
      Profiles::OptionSelections.replace!(profile:, selections: compatibility_values)
      profile.update!(status: :active, visibility: :visible)
    end

    get "/api/v1/find", headers: bearer_headers(@token), params: { limit: 1 }
    first = JSON.parse(response.body)
    compatibility = first.fetch("profiles").sole.fetch("compatibility")

    assert_response :success
    assert_equal "dateza_v1", compatibility.fetch("version")
    assert_equal "high", compatibility.fetch("confidence_level")
    assert_equal 100, compatibility.fetch("score")
    assert_equal 1, first.dig("allowance", "used")
    assert_equal 1, FindProfileExposure.where(brand: @brand, viewer_profile: @viewer).count

    get "/api/v1/find", headers: bearer_headers(@token), params: { limit: 1 }
    reloaded = JSON.parse(response.body)

    assert_equal compatibility, reloaded.fetch("profiles").sole.fetch("compatibility")
    assert_equal 1, reloaded.dig("allowance", "used")
    assert_equal 1, FindProfileExposure.where(brand: @brand, viewer_profile: @viewer).count
  end

  test "projects opener_state (not HookUs's hook_state) onto Find candidates" do
    candidate = create_candidate

    get "/api/v1/find", headers: bearer_headers(@token)
    entry = JSON.parse(response.body).fetch("profiles").sole
    assert_equal "available", entry.fetch("opener_state")
    assert_not entry.key?("hook_state")

    post "/api/v1/profiles/#{candidate.public_id}/opener",
      headers: bearer_headers(@token), params: { opener_key: "coffee_or_tea" }
    assert_response :created

    get "/api/v1/find", headers: bearer_headers(@token)
    assert_equal "pending", JSON.parse(response.body).fetch("profiles").sole.fetch("opener_state")
  end

  test "a processed pending-review DateZA photo is deliverable in Find results" do
    candidate = create_candidate
    photo = attach_photo(candidate)

    get "/api/v1/find", headers: bearer_headers(@token)
    photos = JSON.parse(response.body).fetch("profiles").sole.fetch("photos")

    assert_equal [ photo.public_id ], photos.map { |entry| entry.fetch("id") }
  end

  private

  def attach_photo(profile)
    initial = Media::PhotoPolicy.initial_state(brand: profile.brand)
    photo = ProfilePhoto.new(
      brand: profile.brand, user: profile.user, profile:, status: initial.status, visibility: initial.visibility
    )
    fixture = Rails.root.join("test/fixtures/files/profile_photo.png")
    photo.image.attach(io: fixture.open, filename: "original.png", content_type: "image/png")
    photo.save!
    photo.display_image.attach(io: fixture.open, filename: "display.jpg", content_type: "image/jpeg")
    photo.update!(processing_state: :ready)
    photo
  end

  def create_candidate(**attributes)
    profile = create_profile(
      brand: @brand, gender: "man", age: 30, interested_in: [ "woman" ],
      min_age: 18, max_age: 60, max_distance_km: 100, **attributes
    )
    create_location(profile, latitude: -26.205, longitude: 28.048)
    profile
  end

  def create_profile(brand:, gender:, age:, interested_in:, min_age:, max_age:, max_distance_km: nil,
    profile_attributes: {}, membership_status: :active, user_status: :active, created_at: nil)
    user = User.create!(status: user_status)
    membership = BrandMembership.create!(brand:, user:, status: membership_status)
    profile = Profile.create!(
      brand:, user:, brand_membership: membership, gender:, birthdate: age.years.ago.to_date,
      status: :active, visibility: :visible, **profile_attributes
    )
    profile.update_columns(created_at:, updated_at: created_at) if created_at
    ProfilePreference.create!(
      brand:, user:, profile:, interested_in:, min_age:, max_age:, max_distance_km:
    )
    profile
  end

  def create_location(profile, latitude:, longitude:, captured_at: Time.current)
    ProfileLocation.create!(
      profile:, user: profile.user, brand: profile.brand, latitude:, longitude:,
      accuracy_meters: 20, source: "device", captured_at:
    )
  end

  def select_relationship_intent(profile, code)
    Profiles::OptionSelections.replace!(profile:, selections: { relationship_intent: [ code ] })
    profile.update!(status: :active, visibility: :visible)
  end

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end
end
