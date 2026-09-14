require "test_helper"

class Api::V1::Admin::TrustAdjustmentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @brand = Brand.create!(slug: "date9ja", name: "Date9ja")
    BrandDomain.create!(brand: @brand, host: "date9ja.test")
    @profile = create_profile(brand: @brand)
    @admin, @token = create_admin(brand: @brand, role_name: "trust_safety")
    host! "date9ja.test"
  end

  test "requires the trust_adjustments capability" do
    post "/api/v1/admin/profiles/#{@profile.public_id}/trust_adjustments", params: { points: -20, reason_code: "policy_violation", idempotency_key: "k1" }
    assert_response :unauthorized

    ordinary_token, = Session.issue!(brand: @brand, user: @profile.user)
    post "/api/v1/admin/profiles/#{@profile.public_id}/trust_adjustments",
      headers: bearer_headers(ordinary_token), params: { points: -20, reason_code: "policy_violation", idempotency_key: "k1" }
    assert_response :forbidden
  end

  test "creates and lists a trust adjustment for the profile's user" do
    post "/api/v1/admin/profiles/#{@profile.public_id}/trust_adjustments", headers: bearer_headers(@token),
      params: { points: -20, reason_code: "policy_violation", idempotency_key: "k1", note: "warned" }

    assert_response :created
    body = JSON.parse(response.body).fetch("trust_adjustment")
    assert_equal(-20, body.fetch("points"))
    assert_equal "policy_violation", body.fetch("reason_code")
    assert_equal @profile.public_id, body.fetch("profile_id")

    get "/api/v1/admin/profiles/#{@profile.public_id}/trust_adjustments", headers: bearer_headers(@token)
    assert_response :success
    assert_equal 1, JSON.parse(response.body).fetch("trust_adjustments").size
  end

  test "rejects non-negative points" do
    post "/api/v1/admin/profiles/#{@profile.public_id}/trust_adjustments", headers: bearer_headers(@token),
      params: { points: 5, reason_code: "policy_violation", idempotency_key: "k1" }

    assert_response :unprocessable_entity
    assert_equal "invalid_adjustment_points", JSON.parse(response.body).fetch("error")
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
