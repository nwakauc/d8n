require "test_helper"

class Api::V1::HookTonightControllerTest < ActionDispatch::IntegrationTest
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

  # --- Authentication ------------------------------------------------------

  test "every endpoint requires authentication" do
    get "/api/v1/hook_tonight"
    assert_response :unauthorized
    post "/api/v1/hook_tonight"
    assert_response :unauthorized
    delete "/api/v1/hook_tonight"
    assert_response :unauthorized
    get "/api/v1/hook_tonight/discovery"
    assert_response :unauthorized
  end

  # --- Activation ----------------------------------------------------------

  test "an eligible member activates and receives their live state" do
    post "/api/v1/hook_tonight", headers: bearer_headers(@token)

    assert_response :created
    body = JSON.parse(response.body)
    assert body.fetch("active")
    assert body.fetch("expires_at").present?
    assert_equal "open_to_meeting", body.fetch("intent")
    assert HookTonightState.live.exists?(brand: @brand, profile: @viewer)
  end

  test "duplicate activation refreshes the single row rather than duplicating" do
    post "/api/v1/hook_tonight", headers: bearer_headers(@token)
    assert_response :created
    post "/api/v1/hook_tonight", headers: bearer_headers(@token)
    assert_response :created

    assert_equal 1, HookTonightState.where(brand: @brand, profile: @viewer).count
  end

  test "a suspended member cannot activate" do
    @viewer.update!(status: :suspended)

    post "/api/v1/hook_tonight", headers: bearer_headers(@token)

    assert_response :forbidden
    assert_equal "discoverable_profile_required", JSON.parse(response.body).fetch("error")
    assert_empty HookTonightState.where(brand: @brand)
  end

  test "a closed member cannot activate" do
    @viewer.update!(deleted_at: Time.current)

    post "/api/v1/hook_tonight", headers: bearer_headers(@token)

    assert_response :forbidden
    assert_empty HookTonightState.where(brand: @brand)
  end

  test "an unsupported intent is rejected" do
    post "/api/v1/hook_tonight", headers: bearer_headers(@token), params: { intent: "netflix" }

    assert_response :unprocessable_entity
    assert_equal "invalid_intent", JSON.parse(response.body).fetch("error")
    assert_empty HookTonightState.where(brand: @brand)
  end

  # --- Current state -------------------------------------------------------

  test "current state is inactive before activation" do
    get "/api/v1/hook_tonight", headers: bearer_headers(@token)

    assert_response :success
    body = JSON.parse(response.body)
    assert_not body.fetch("active")
    assert_nil body.fetch("expires_at")
    assert_nil body.fetch("intent")
  end

  test "current state is active after activation" do
    post "/api/v1/hook_tonight", headers: bearer_headers(@token)

    get "/api/v1/hook_tonight", headers: bearer_headers(@token)

    assert_response :success
    assert JSON.parse(response.body).fetch("active")
  end

  test "a stale expired activation authoritatively reads as inactive" do
    post "/api/v1/hook_tonight", headers: bearer_headers(@token)
    HookTonightState.find_by!(brand: @brand, profile: @viewer).update_columns(expires_at: 1.hour.ago)

    get "/api/v1/hook_tonight", headers: bearer_headers(@token)

    assert_response :success
    assert_not JSON.parse(response.body).fetch("active")
  end

  # --- Deactivation --------------------------------------------------------

  test "deactivation turns availability off immediately" do
    post "/api/v1/hook_tonight", headers: bearer_headers(@token)

    delete "/api/v1/hook_tonight", headers: bearer_headers(@token)
    assert_response :no_content

    get "/api/v1/hook_tonight", headers: bearer_headers(@token)
    assert_not JSON.parse(response.body).fetch("active")
  end

  test "repeat deactivation is a safe no-op" do
    delete "/api/v1/hook_tonight", headers: bearer_headers(@token)
    assert_response :no_content
    delete "/api/v1/hook_tonight", headers: bearer_headers(@token)
    assert_response :no_content
  end

  # --- Discovery -----------------------------------------------------------

  test "viewing the pool requires the viewer to be in the pool" do
    available = create_candidate
    activate(available)

    get "/api/v1/hook_tonight/discovery", headers: bearer_headers(@token)

    assert_response :forbidden
    assert_equal "hook_tonight_required", JSON.parse(response.body).fetch("error")
  end

  test "discovery returns only available compatible members" do
    activate(@viewer)
    available = create_candidate(display_name: "Available")
    activate(available)
    create_candidate(display_name: "NotAvailable")

    get "/api/v1/hook_tonight/discovery", headers: bearer_headers(@token)

    assert_response :success
    profiles = JSON.parse(response.body).fetch("profiles")
    assert_equal [ available.public_id ], profiles.pluck("id")
    assert_equal "available", profiles.sole.fetch("hook_state")
  end

  test "client mode cannot redirect Hook Tonight away from its configured restricted surface" do
    activate(@viewer)
    available = create_candidate(display_name: "Available")
    activate(available)

    get "/api/v1/hook_tonight/discovery",
      headers: bearer_headers(@token), params: { mode: "unknown" }

    assert_response :success
    assert_equal [ available.public_id ], JSON.parse(response.body).fetch("profiles").pluck("id")
  end

  test "discovery excludes expired, deactivated, suspended, closed, blocked, and cross-brand availability" do
    activate(@viewer)
    expired = create_candidate
    activate(expired).update_columns(expires_at: 1.hour.ago)
    deactivated = create_candidate
    HookTonight::Deactivate.call(user: activate(deactivated).profile.user, brand: @brand)
    suspended = create_candidate
    activate(suspended)
    suspended.update!(status: :suspended)
    closed = create_candidate
    activate(closed)
    closed.update!(deleted_at: Time.current)
    blocked = create_candidate
    activate(blocked)
    ProfileBlock.create!(brand: @brand, blocker_profile: blocked, blocked_profile: @viewer)
    other_brand = Brand.create!(slug: "other", name: "Other")
    cross = create_profile(
      brand: other_brand, gender: "man", age: 30, interested_in: [ "woman" ], min_age: 25, max_age: 40
    )
    HookTonight::Activate.call(user: cross.user, brand: other_brand)

    get "/api/v1/hook_tonight/discovery", headers: bearer_headers(@token)

    assert_response :success
    assert_empty JSON.parse(response.body).fetch("profiles")
  end

  test "discovery never exposes coordinates and reuses approximate distance" do
    activate(@viewer)
    candidate = create_candidate(display_name: "Near")
    activate(candidate)
    create_location(@viewer)
    create_location(candidate)

    get "/api/v1/hook_tonight/discovery", headers: bearer_headers(@token)

    assert_response :success
    profile = JSON.parse(response.body).fetch("profiles").sole
    assert_equal 1, profile.fetch("distance_km")
    assert_not profile.key?("latitude")
    assert_not profile.key?("longitude")
    assert_not_includes response.body, "-33.9249"
  end

  test "discovery requires a discoverable viewer" do
    @viewer.update!(status: :draft)

    get "/api/v1/hook_tonight/discovery", headers: bearer_headers(@token)

    assert_response :forbidden
    assert_equal "discoverable_profile_required", JSON.parse(response.body).fetch("error")
  end

  test "discovery rejects invalid limits and tampered cursors" do
    activate(@viewer)
    get "/api/v1/hook_tonight/discovery", headers: bearer_headers(@token), params: { limit: 51 }
    assert_response :unprocessable_entity
    assert_equal "invalid_limit", JSON.parse(response.body).fetch("error")

    get "/api/v1/hook_tonight/discovery", headers: bearer_headers(@token), params: { cursor: "nope" }
    assert_response :unprocessable_entity
    assert_equal "invalid_cursor", JSON.parse(response.body).fetch("error")
  end

  test "discovery does not introduce per-profile queries as the pool grows" do
    activate(@viewer)
    first = create_candidate
    activate(first)

    baseline = count_select_queries do
      get "/api/v1/hook_tonight/discovery", headers: bearer_headers(@token)
    end

    4.times { activate(create_candidate) }

    grown = count_select_queries do
      get "/api/v1/hook_tonight/discovery", headers: bearer_headers(@token)
    end

    assert_response :success
    assert_equal 5, JSON.parse(response.body).fetch("profiles").size
    assert_operator grown, :<=, baseline + 1
  end

  # --- Existing Hook integration ------------------------------------------

  test "the existing Hook endpoint is the approach path and creates no conversation" do
    candidate = create_candidate
    activate(candidate)

    post "/api/v1/profiles/#{candidate.public_id}/hook",
      headers: bearer_headers(@token), params: { message: "You're my vibe 🔥" }

    assert_response :created
    assert Hook.live.exists?(brand: @brand, sender_profile: @viewer, recipient_profile: candidate)
    assert_equal 0, Conversation.where(brand: @brand).count
    assert_equal 0, Match.where(brand: @brand).count
  end

  test "a member the viewer has Hooked drops out of Hook Tonight discovery" do
    activate(@viewer)
    candidate = create_candidate
    activate(candidate)
    post "/api/v1/profiles/#{candidate.public_id}/hook",
      headers: bearer_headers(@token), params: { message: "hi 🔥" }
    assert_response :created

    get "/api/v1/hook_tonight/discovery", headers: bearer_headers(@token)

    assert_response :success
    assert_empty JSON.parse(response.body).fetch("profiles")
  end

  test "Hook Tonight grants no extra Hook allowance — the existing daily limit still applies" do
    Hooks::Policy::FREE_DAILY_LIMIT.times do
      target = create_candidate
      Hooks::SendHook.call(
        user: @viewer.user, brand: @brand, target_public_id: target.public_id,
        message: "opener 🔥", eligibility_policy: D8n::Platform::Brands::Hookus::ELIGIBILITY_POLICY
      )
    end
    available = create_candidate
    activate(available)

    post "/api/v1/profiles/#{available.public_id}/hook",
      headers: bearer_headers(@token), params: { message: "one more 🔥" }

    assert_response :too_many_requests
    assert_equal "hook_rate_limited", JSON.parse(response.body).fetch("error")
  end

  private

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end

  def activate(profile)
    HookTonight::Activate.call(user: profile.user, brand: profile.brand).state
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
