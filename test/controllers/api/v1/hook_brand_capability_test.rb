require "test_helper"

class Api::V1::HookBrandCapabilityTest < ActionDispatch::IntegrationTest
  setup do
    @dateza = Brand.create!(slug: "dateza", name: "DateZA")
    BrandDomain.create!(brand: @dateza, host: "dateza.test")
    @viewer = create_profile(brand: @dateza, gender: "woman", interested_in: [ "man" ])
    @target = create_profile(brand: @dateza, gender: "man", interested_in: [ "woman" ])
    @identifier = IdentityIdentifier.create!(
      user: @viewer.user, kind: :email, normalized_value: "dateza-hooks@example.com", verified_at: Time.current
    )
    credential = Credential.create!(user: @viewer.user, identity_identifier: @identifier, kind: :password)
    @token, = Session.issue!(brand: @dateza, user: @viewer.user, credential:)
    host! "dateza.test"
  end

  test "DateZA cannot send or list Hooks and capability denial precedes verification" do
    assert_no_difference -> { Hook.count } do
      post "/api/v1/profiles/#{@target.public_id}/hook",
        headers: bearer_headers(@token), params: { message: "Not available on DateZA" }
    end
    assert_feature_unavailable("hook_not_configured")

    @identifier.update!(verified_at: nil)
    get "/api/v1/hooks", headers: bearer_headers(@token)
    assert_feature_unavailable("hook_not_configured")
  end

  test "DateZA cannot reply to or decline a legacy Hook and no state mutates" do
    hook = Hook.create!(
      brand: @dateza, sender_profile: @target, recipient_profile: @viewer,
      message: "Legacy opener", expires_at: 1.hour.from_now
    )

    assert_no_difference [ -> { Match.count }, -> { Conversation.count }, -> { Message.count } ] do
      post "/api/v1/hooks/#{hook.public_id}/reply",
        headers: bearer_headers(@token), params: { message: "No" }
    end
    assert_feature_unavailable("hook_not_configured")
    assert hook.reload.status_pending?

    assert_no_changes -> { hook.reload.status } do
      post "/api/v1/hooks/#{hook.public_id}/decline", headers: bearer_headers(@token)
    end
    assert_feature_unavailable("hook_not_configured")
    assert_nil hook.reload.declined_at
  end

  test "DateZA cannot read activate or browse Hook Tonight and no activation is created" do
    get "/api/v1/hook_tonight", headers: bearer_headers(@token)
    assert_feature_unavailable("hook_tonight_not_configured")

    assert_no_difference -> { HookTonightState.count } do
      post "/api/v1/hook_tonight", headers: bearer_headers(@token)
    end
    assert_feature_unavailable("hook_tonight_not_configured")

    get "/api/v1/hook_tonight/discovery", headers: bearer_headers(@token)
    assert_feature_unavailable("hook_tonight_not_configured")
  end

  test "DateZA may deactivate legacy Hook Tonight state for safe cleanup" do
    state = HookTonightState.create!(
      brand: @dateza, profile: @viewer, intent: HookTonight::Policy::DEFAULT_INTENT,
      activated_at: Time.current, expires_at: 2.hours.from_now
    )

    delete "/api/v1/hook_tonight", headers: bearer_headers(@token)

    assert_response :no_content
    assert state.reload.deactivated_at.present?
  end

  test "HookUs retains Hook and Hook Tonight capability" do
    hookus = Brand.create!(slug: "hookus", name: "HookUs")
    BrandDomain.create!(brand: hookus, host: "hookus.test")
    viewer = create_profile(brand: hookus, gender: "woman", interested_in: [ "man" ])
    target = create_profile(brand: hookus, gender: "man", interested_in: [ "woman" ])
    token, = Session.issue!(brand: hookus, user: viewer.user)
    host! "hookus.test"

    assert_difference -> { Hook.count }, 1 do
      post "/api/v1/profiles/#{target.public_id}/hook",
        headers: bearer_headers(token), params: { message: "Hello" }
    end
    assert_response :created

    assert_difference -> { HookTonightState.count }, 1 do
      post "/api/v1/hook_tonight", headers: bearer_headers(token)
    end
    assert_response :created
  end

  test "a DateZA session cannot cross into HookUs to use its enabled capability" do
    hookus = Brand.create!(slug: "hookus", name: "HookUs")
    BrandDomain.create!(brand: hookus, host: "hookus.test")
    hookus_target = create_profile(brand: hookus, gender: "man", interested_in: [ "woman" ])
    host! "hookus.test"

    assert_no_difference -> { Hook.count } do
      post "/api/v1/profiles/#{hookus_target.public_id}/hook",
        headers: bearer_headers(@token), params: { message: "Cross brand" }
    end
    assert_response :unauthorized
    assert_equal "unauthorized", JSON.parse(response.body).fetch("error")
  end

  private

  def assert_feature_unavailable(code)
    assert_response :not_found
    assert_equal({ "error" => code }, JSON.parse(response.body))
  end

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

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end
end
