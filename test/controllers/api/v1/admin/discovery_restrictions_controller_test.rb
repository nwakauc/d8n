require "test_helper"

class Api::V1::Admin::DiscoveryRestrictionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @brand = Brand.create!(slug: "date9ja", name: "Date9ja")
    BrandDomain.create!(brand: @brand, host: "date9ja.test")
    @profile = create_profile(brand: @brand)
    @admin, @token = create_admin(brand: @brand, role_name: "trust_safety")
    host! "date9ja.test"
  end

  test "requires the discovery_restrictions capability" do
    post "/api/v1/admin/profiles/#{@profile.public_id}/discovery_restriction", params: { reason: "spam reports" }
    assert_response :unauthorized

    ordinary_token, = Session.issue!(brand: @brand, user: @profile.user)
    post "/api/v1/admin/profiles/#{@profile.public_id}/discovery_restriction",
      headers: bearer_headers(ordinary_token), params: { reason: "spam reports" }
    assert_response :forbidden
  end

  test "requires MFA" do
    user = User.create!
    BrandMembership.create!(brand: @brand, user:)
    admin_user = AdminUser.create!(user:, status: :active)
    role = AdminRole.find_or_create_by!(name: "trust_safety")
    AdminAssignment.create!(admin_user:, brand: @brand, admin_role: role, status: :active)
    token, = Session.issue!(brand: @brand, user:)

    post "/api/v1/admin/profiles/#{@profile.public_id}/discovery_restriction",
      headers: bearer_headers(token), params: { reason: "spam reports" }

    assert_response :forbidden
    assert_equal "admin_mfa_required", JSON.parse(response.body).fetch("error")
  end

  test "hides a profile from discovery without touching account status, then unhides it" do
    assert_difference -> { SecurityEvent.where(event_type: "admin.discovery_restricted").count }, 1 do
      post "/api/v1/admin/profiles/#{@profile.public_id}/discovery_restriction",
        headers: bearer_headers(@token), params: { reason: "spam reports", note: "watch list" }
    end
    assert_response :created
    body = JSON.parse(response.body).fetch("profile")
    assert body.fetch("discovery_restricted")
    assert_equal @profile.public_id, body.fetch("profile_id")

    @profile.reload
    assert @profile.discovery_restricted_at.present?
    assert_equal "spam reports", @profile.discovery_restriction_reason
    assert_equal @admin.id, @profile.discovery_restricted_by_admin_user_id
    # Distinct from suspend/ban and pause: account/membership state untouched.
    assert @profile.brand_membership.reload.active?
    refute @profile.suspended?

    event = SecurityEvent.where(event_type: "admin.discovery_restricted").last
    assert_not_includes event.metadata.to_s, "spam reports"

    assert_difference -> { SecurityEvent.where(event_type: "admin.discovery_restriction_lifted").count }, 1 do
      delete "/api/v1/admin/profiles/#{@profile.public_id}/discovery_restriction", headers: bearer_headers(@token)
    end
    assert_response :success
    refute JSON.parse(response.body).fetch("profile").fetch("discovery_restricted")
    refute @profile.reload.discovery_restricted_at.present?
  end

  test "a restricted profile is excluded from VisibilityScope (discovery and direct view) but not from being logged in" do
    other = create_profile(brand: @brand)
    Admin::RestrictProfileDiscovery.call(admin_user: @admin, brand: @brand, profile_public_id: @profile.public_id, reason: "under review")

    scope = Matching::VisibilityScope.call(brand: @brand, viewer: other)
    refute_includes scope, @profile

    token, = Session.issue!(brand: @brand, user: @profile.user)
    assert token.present?
  end

  test "cannot restrict an already-restricted profile, and cannot lift a non-restricted one" do
    post "/api/v1/admin/profiles/#{@profile.public_id}/discovery_restriction",
      headers: bearer_headers(@token), params: { reason: "spam reports" }
    assert_response :created

    post "/api/v1/admin/profiles/#{@profile.public_id}/discovery_restriction",
      headers: bearer_headers(@token), params: { reason: "again" }
    assert_response :conflict
    assert_equal "already_restricted", JSON.parse(response.body).fetch("error")

    other = create_profile(brand: @brand)
    delete "/api/v1/admin/profiles/#{other.public_id}/discovery_restriction", headers: bearer_headers(@token)
    assert_response :conflict
    assert_equal "not_restricted", JSON.parse(response.body).fetch("error")
  end

  test "a cross-brand target is not disclosed" do
    other_brand = Brand.create!(slug: "hookus", name: "HookUs")
    foreign = create_profile(brand: other_brand)

    post "/api/v1/admin/profiles/#{foreign.public_id}/discovery_restriction",
      headers: bearer_headers(@token), params: { reason: "spam reports" }
    assert_response :not_found
    assert_equal "profile_unavailable", JSON.parse(response.body).fetch("error")
  end

  test "a reason is required" do
    post "/api/v1/admin/profiles/#{@profile.public_id}/discovery_restriction", headers: bearer_headers(@token)
    assert_response :unprocessable_entity
    assert_equal "invalid_reason", JSON.parse(response.body).fetch("error")
  end

  private

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end

  def create_profile(brand:)
    user = User.create!
    membership = BrandMembership.create!(brand:, user:)
    Profile.create!(brand:, user:, brand_membership: membership)
  end

  def create_admin(brand:, role_name: "moderator")
    user = User.create!
    BrandMembership.create!(brand:, user:)
    admin_user = AdminUser.create!(user:, status: :active)
    role = AdminRole.find_or_create_by!(name: role_name)
    AdminAssignment.create!(admin_user:, brand:, admin_role: role, status: :active)
    token = issue_mfa_verified_admin_session!(user:, brand:, admin_user:)
    [ admin_user, token ]
  end
end
