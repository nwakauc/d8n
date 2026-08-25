require "test_helper"

class Api::V1::PlatformCapabilityGateTest < ActionDispatch::IntegrationTest
  setup do
    @brand = Brand.create!(slug: "future-brand", name: "Future Brand")
    BrandDomain.create!(brand: @brand, host: "future.test")
    @viewer = create_profile(brand: @brand, gender: "woman", interested_in: [ "man" ])
    @target = create_profile(brand: @brand, gender: "man", interested_in: [ "woman" ])
    @token, = Session.issue!(brand: @brand, user: @viewer.user)
    host! "future.test"
  end

  test "authentication runs before capability authorization" do
    get "/api/v1/discovery"

    assert_response :unauthorized
    assert_equal({ "error" => "unauthorized" }, JSON.parse(response.body))
  end

  test "unsupported candidate surfaces fail closed without consuming product rate limits" do
    assert_no_difference -> { RateLimitCounter.count } do
      get "/api/v1/discovery", headers: bearer_headers
    end
    assert_not_configured("brand_not_configured")

    assert_no_difference -> { RateLimitCounter.count } do
      get "/api/v1/find", headers: bearer_headers
    end
    assert_not_configured("brand_not_configured")
  end

  test "unsupported matching surfaces share the stable brand contract error" do
    post "/api/v1/profiles/#{@target.public_id}/likes", headers: bearer_headers
    assert_not_configured("brand_not_configured")

    post "/api/v1/profiles/#{@target.public_id}/pass", headers: bearer_headers
    assert_not_configured("brand_not_configured")

    get "/api/v1/matches", headers: bearer_headers
    assert_not_configured("brand_not_configured")
  end

  test "unsupported messaging surfaces fail before resource lookup" do
    get "/api/v1/conversations", headers: bearer_headers
    assert_not_configured("brand_not_configured")

    post "/api/v1/matches/not-a-match/conversation", headers: bearer_headers
    assert_not_configured("brand_not_configured")

    get "/api/v1/conversations/not-a-conversation/messages", headers: bearer_headers
    assert_not_configured("brand_not_configured")

    post "/api/v1/conversations/not-a-conversation/messages",
      headers: bearer_headers, params: { body: "must not be accepted" }
    assert_not_configured("brand_not_configured")
  end

  test "unsupported Hook surfaces fail at the brand contract boundary" do
    post "/api/v1/profiles/#{@target.public_id}/hook",
      headers: bearer_headers, params: { message: "not configured" }
    assert_not_configured("brand_not_configured")

    get "/api/v1/hooks", headers: bearer_headers
    assert_not_configured("brand_not_configured")

    get "/api/v1/hook_tonight", headers: bearer_headers
    assert_not_configured("brand_not_configured")

    post "/api/v1/hook_tonight", headers: bearer_headers
    assert_not_configured("brand_not_configured")

    get "/api/v1/hook_tonight/discovery", headers: bearer_headers
    assert_not_configured("brand_not_configured")
  end

  test "Hook Tonight cleanup cannot bypass the production brand contract" do
    state = HookTonightState.create!(
      brand: @brand,
      profile: @viewer,
      intent: HookTonight::Policy::DEFAULT_INTENT,
      activated_at: Time.current,
      expires_at: 1.hour.from_now
    )

    assert_no_changes -> { state.reload.deactivated_at } do
      delete "/api/v1/hook_tonight", headers: bearer_headers
    end

    assert_not_configured("brand_not_configured")
  end

  test "unsupported brands cannot probe or mutate a profile from a production brand" do
    hookus = Brand.create!(slug: "hookus", name: "HookUs")
    target = create_profile(brand: hookus, gender: "man", interested_in: [ "woman" ])

    assert_no_difference [ -> { Like.count }, -> { Match.count }, -> { ProfilePass.count } ] do
      post "/api/v1/profiles/#{target.public_id}/likes", headers: bearer_headers
    end
    assert_not_configured("brand_not_configured")

    assert_no_difference [ -> { Like.count }, -> { Match.count }, -> { ProfilePass.count } ] do
      post "/api/v1/profiles/#{SecureRandom.uuid}/likes", headers: bearer_headers
    end
    assert_not_configured("brand_not_configured")
  end

  test "unknown hosts retain authentication-first behavior" do
    host! "unknown.test"

    post "/api/v1/profiles/#{@target.public_id}/likes", headers: bearer_headers

    assert_response :unauthorized
    assert_equal({ "error" => "unauthorized" }, JSON.parse(response.body))
  end

  test "ungated profile detail remains a shared profile capability" do
    get "/api/v1/profiles/#{@target.public_id}", headers: bearer_headers

    assert_response :success
    profile = JSON.parse(response.body).fetch("profile")
    assert_equal @target.public_id, profile.fetch("id")
    assert_not profile.key?("hook_state")
    assert_not profile.key?("hook_tonight_active")
  end

  private

  def create_profile(brand:, gender:, interested_in:)
    user = User.create!
    membership = BrandMembership.create!(brand:, user:)
    profile = Profile.create!(
      brand:, user:, brand_membership: membership, display_name: "Member", gender:,
      birthdate: 30.years.ago.to_date, status: :active, visibility: :visible
    )
    ProfilePreference.create!(
      brand:, user:, profile:, min_age: 18, max_age: 60, interested_in:
    )
    profile
  end

  def bearer_headers
    { "Authorization" => "Bearer #{@token}" }
  end

  def assert_not_configured(code)
    assert_response :not_found
    assert_equal({ "error" => code }, JSON.parse(response.body))
  end
end
