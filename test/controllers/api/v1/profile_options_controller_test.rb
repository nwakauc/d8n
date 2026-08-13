require "test_helper"

class Api::V1::ProfileOptionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @brand = Brand.create!(slug: "hookus", name: "HookUs")
    Profiles::HookusProfileCatalog.install!(brand: @brand)
    BrandDomain.create!(brand: @brand, host: "hookus.test")
    @user = User.create!
    membership = BrandMembership.create!(brand: @brand, user: @user)
    @profile = Profile.create!(brand: @brand, user: @user, brand_membership: membership)
    @token, = Session.issue!(brand: @brand, user: @user)
    host! "hookus.test"
  end

  test "requires authentication and a current brand profile" do
    patch "/api/v1/profile/options", params: { selections: { intents: [ "hookups" ] } }
    assert_response :unauthorized

    @profile.destroy!
    patch "/api/v1/profile/options",
      headers: bearer_headers(@token),
      params: { selections: { intents: [ "hookups" ] } }

    assert_response :forbidden
    assert_equal "profile_required", JSON.parse(response.body).fetch("error")
  end

  test "updates selected intents and vibes" do
    patch "/api/v1/profile/options",
      headers: bearer_headers(@token),
      params: { selections: { intents: %w[ hookups casual ], vibes: %w[ nightlife music ] } }

    assert_response :success
    profile_payload = JSON.parse(response.body).fetch("profile")
    assert_equal %w[ hookups casual ], profile_payload.fetch("options").fetch("intents")
    assert_equal %w[ nightlife music ], profile_payload.fetch("options").fetch("vibes")
    assert_equal 4, @profile.profile_option_selections.kept.count
  end

  test "rejects unsupported current-brand options" do
    patch "/api/v1/profile/options",
      headers: bearer_headers(@token),
      params: { selections: { intents: [ "marriage_only" ] } }

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_equal "invalid_profile_options", body.fetch("error")
    assert body.fetch("details").fetch("intents").first.include?("unsupported")
  end

  test "rejects malformed option payloads" do
    patch "/api/v1/profile/options",
      headers: bearer_headers(@token),
      params: { selections: "intents" }

    assert_response :unprocessable_entity
    assert_equal "invalid_profile_options", JSON.parse(response.body).fetch("error")

    patch "/api/v1/profile/options",
      headers: bearer_headers(@token),
      params: { selections: { intents: [ 1 ] } },
      as: :json

    assert_response :unprocessable_entity
    assert JSON.parse(response.body).fetch("details").fetch("intents").first.include?("string")
  end

  private

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end
end
