require "test_helper"

class DatezaTenantFoundationTest < ActionDispatch::IntegrationTest
  HOOKUS_HOST = "staging-api.d8n.tech".freeze
  DATEZA_HOST = "dateza-staging-api.d8n.tech".freeze

  setup do
    @hookus = Brand.create!(slug: "hookus", name: "HookUs")
    Profiles::HookusProfileCatalog.install!(brand: @hookus)
    BrandDomain.create!(brand: @hookus, host: HOOKUS_HOST)

    @dateza = Brands::DatezaInstaller.call(hosts: [ DATEZA_HOST ])
  end

  test "resolves each brand and advertises only its configured authentication methods" do
    host! DATEZA_HOST
    get "/api/v1/auth/methods"

    assert_response :success
    assert_equal(
      {
        "brand" => { "slug" => "dateza", "name" => "DateZA" },
        "methods" => %w[ phone_password email_password ]
      },
      JSON.parse(response.body)
    )

    host! HOOKUS_HOST
    get "/api/v1/auth/methods"

    assert_response :success
    assert_equal "hookus", JSON.parse(response.body).dig("brand", "slug")
  end

  test "brand-bound sessions cannot be replayed across DateZA and HookUs" do
    user = User.create!
    BrandMembership.create!(brand: @dateza, user:)
    BrandMembership.create!(brand: @hookus, user:)
    dateza_token, = Session.issue!(brand: @dateza, user:)
    hookus_token, = Session.issue!(brand: @hookus, user:)

    host! HOOKUS_HOST
    get "/api/v1/profile/configuration", headers: bearer_headers(dateza_token)
    assert_response :unauthorized

    host! DATEZA_HOST
    get "/api/v1/profile/configuration", headers: bearer_headers(hookus_token)
    assert_response :unauthorized

    get "/api/v1/profile/configuration", headers: bearer_headers(dateza_token)
    assert_response :success
  end

  test "one identity has separate memberships and profiles without configuration leakage" do
    user = User.create!
    hookus_membership = BrandMembership.create!(brand: @hookus, user:)
    dateza_membership = BrandMembership.create!(brand: @dateza, user:)
    hookus_profile = create_profile(brand: @hookus, user:, membership: hookus_membership, name: "Hook Profile")
    dateza_profile = create_profile(brand: @dateza, user:, membership: dateza_membership, name: "DateZA Profile")
    hookus_token, = Session.issue!(brand: @hookus, user:)
    dateza_token, = Session.issue!(brand: @dateza, user:)

    assert_not_equal hookus_profile.public_id, dateza_profile.public_id
    assert_equal 2, BrandMembership.kept.where(user:).count
    assert_equal 2, Profile.kept.where(user:).count

    host! DATEZA_HOST
    get "/api/v1/profile/configuration", headers: bearer_headers(dateza_token)
    assert_response :success
    dateza_groups = JSON.parse(response.body).dig("configuration", "option_groups").pluck("key")
    assert_includes dateza_groups, "relationship_intent"
    assert_not_includes dateza_groups, "intents"
    assert_not_includes dateza_groups, "vibes"

    host! HOOKUS_HOST
    get "/api/v1/profile/configuration", headers: bearer_headers(hookus_token)
    assert_response :success
    hookus_groups = JSON.parse(response.body).dig("configuration", "option_groups").pluck("key")
    assert_includes hookus_groups, "intents"
    assert_includes hookus_groups, "vibes"
    assert_not_includes hookus_groups, "relationship_intent"
  end

  test "cross-brand public profile identifiers fail neutrally" do
    dateza_viewer = create_member_profile(brand: @dateza, name: "DateZA Viewer")
    hookus_target = create_member_profile(brand: @hookus, name: "HookUs Target")
    token, = Session.issue!(brand: @dateza, user: dateza_viewer.user)

    host! DATEZA_HOST
    get "/api/v1/profiles/#{hookus_target.public_id}", headers: bearer_headers(token)

    assert_response :not_found
    assert_equal({ "error" => "profile_unavailable" }, JSON.parse(response.body))
  end

  test "DateZA matching stays unavailable until a production strategy is implemented" do
    viewer = create_member_profile(brand: @dateza, name: "DateZA Viewer")
    token, = Session.issue!(brand: @dateza, user: viewer.user)

    host! DATEZA_HOST
    get "/api/v1/discovery", headers: bearer_headers(token)

    assert_response :not_found
    assert_equal({ "error" => "matching_not_configured" }, JSON.parse(response.body))
  end

  test "leaving DateZA preserves the other brand membership profile and session" do
    user = User.create!
    hookus_membership = BrandMembership.create!(brand: @hookus, user:)
    dateza_membership = BrandMembership.create!(brand: @dateza, user:)
    hookus_profile = create_profile(brand: @hookus, user:, membership: hookus_membership, name: "Hook Profile")
    create_profile(brand: @dateza, user:, membership: dateza_membership, name: "DateZA Profile")
    hookus_token, = Session.issue!(brand: @hookus, user:)
    dateza_token, = Session.issue!(brand: @dateza, user:)

    host! DATEZA_HOST
    delete "/api/v1/me", params: { confirmation: "close" }, headers: bearer_headers(dateza_token)
    assert_response :success

    assert dateza_membership.reload.left?
    assert hookus_membership.reload.active?
    assert Profile.kept.exists?(hookus_profile.id)

    host! HOOKUS_HOST
    get "/api/v1/me", headers: bearer_headers(hookus_token)
    assert_response :success
    assert_equal "hookus", JSON.parse(response.body).dig("brand", "slug")
  end

  test "DateZA registration reaches authenticated DateZA profile configuration" do
    host! DATEZA_HOST
    post "/api/v1/auth/password/register", params: {
      identifier: "dateza-foundation@example.test",
      password: "secret",
      device_name: "DateZA Test Web"
    }

    assert_response :created
    registration = JSON.parse(response.body)
    assert_equal "dateza", registration.dig("brand", "slug")
    assert_equal "profile_required", registration.dig("onboarding", "state")

    get "/api/v1/profile/configuration", headers: bearer_headers(registration.fetch("token"))

    assert_response :success
    configuration = JSON.parse(response.body).fetch("configuration")
    onboarding = JSON.parse(response.body).fetch("onboarding")
    assert configuration.fetch("profile_fields").find { |field| field.fetch("key") == "bio" }.fetch("required")
    assert_equal Profiles::DatezaProfileCatalog::ENABLED_CAPABILITIES.pluck(:key).push("interests").sort,
      configuration.fetch("option_groups").pluck("key").sort
    assert_equal "profile_required", onboarding.fetch("state")
    assert_equal "profile", onboarding.fetch("next_step")
  end

  private

  def create_member_profile(brand:, name:)
    user = User.create!
    membership = BrandMembership.create!(brand:, user:)
    create_profile(brand:, user:, membership:, name:)
  end

  def create_profile(brand:, user:, membership:, name:)
    profile = Profile.create!(
      brand:, user:, brand_membership: membership, display_name: name,
      birthdate: 30.years.ago.to_date, gender: "person", status: :active, visibility: :visible
    )
    ProfilePreference.create!(
      brand:, user:, profile:, min_age: 18, max_age: 80, interested_in: [ "person" ]
    )
    profile
  end

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end
end
