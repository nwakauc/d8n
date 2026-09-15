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

  # --- reversal ----------------------------------------------------------

  test "requires the trust_adjustments reverse capability, separate from create" do
    post "/api/v1/admin/profiles/#{@profile.public_id}/trust_adjustments", headers: bearer_headers(@token),
      params: { points: -20, reason_code: "policy_violation", idempotency_key: "k1" }
    adjustment_id = JSON.parse(response.body).fetch("trust_adjustment").fetch("id")

    limited_admin, limited_token = create_admin(brand: @brand, role_name: "support")
    patch "/api/v1/admin/profiles/#{@profile.public_id}/trust_adjustments/#{adjustment_id}/reversal",
      headers: bearer_headers(limited_token), params: { reason: "appeal upheld" }
    assert_response :forbidden
  end

  test "overturning a deduction restores the score, preserves history, and is idempotent" do
    post "/api/v1/admin/profiles/#{@profile.public_id}/trust_adjustments", headers: bearer_headers(@token),
      params: { points: -20, reason_code: "policy_violation", idempotency_key: "k1" }
    adjustment_id = JSON.parse(response.body).fetch("trust_adjustment").fetch("id")

    assert_equal 0, Trust::Ledger.score(user: @profile.user, brand: @brand)

    assert_difference -> { SecurityEvent.where(event_type: "admin.trust_adjustment_reversed").count }, 1 do
      patch "/api/v1/admin/profiles/#{@profile.public_id}/trust_adjustments/#{adjustment_id}/reversal",
        headers: bearer_headers(@token), params: { reason: "appeal upheld" }
    end
    assert_response :success
    body = JSON.parse(response.body).fetch("trust_adjustment")
    assert_equal "overturned", body.fetch("appeal_status")

    # Score recalculates immediately, no compensating adjustment created.
    assert_equal 0, Trust::Ledger.score(user: @profile.user, brand: @brand)
    assert_equal 1, TrustAdjustment.where(brand: @brand, user: @profile.user).count

    adjustment = TrustAdjustment.find(adjustment_id)
    assert_equal(-20, adjustment.points)
    assert_equal "policy_violation", adjustment.reason_code
    assert_equal @admin.id, adjustment.actor_admin_user_id

    event = SecurityEvent.where(event_type: "admin.trust_adjustment_reversed").last
    assert_not_includes event.metadata.to_s, "appeal upheld"

    # Idempotent: reversing again does not raise, re-audit, or change state.
    assert_no_difference -> { SecurityEvent.where(event_type: "admin.trust_adjustment_reversed").count } do
      patch "/api/v1/admin/profiles/#{@profile.public_id}/trust_adjustments/#{adjustment_id}/reversal",
        headers: bearer_headers(@token), params: { reason: "again" }
    end
    assert_response :success
  end

  test "an unknown adjustment id is not disclosed" do
    patch "/api/v1/admin/profiles/#{@profile.public_id}/trust_adjustments/999999/reversal",
      headers: bearer_headers(@token), params: { reason: "x" }
    assert_response :not_found
    assert_equal "adjustment_unavailable", JSON.parse(response.body).fetch("error")
  end

  test "a cross-brand adjustment cannot be reversed from another brand" do
    post "/api/v1/admin/profiles/#{@profile.public_id}/trust_adjustments", headers: bearer_headers(@token),
      params: { points: -20, reason_code: "policy_violation", idempotency_key: "k1" }
    adjustment_id = JSON.parse(response.body).fetch("trust_adjustment").fetch("id")

    other_brand = Brand.create!(slug: "hookus", name: "HookUs")
    BrandDomain.create!(brand: other_brand, host: "hookus.test")
    other_profile = create_profile(brand: other_brand)
    _other_admin, other_token = create_admin(brand: other_brand, role_name: "trust_safety")

    host! "hookus.test"
    patch "/api/v1/admin/profiles/#{other_profile.public_id}/trust_adjustments/#{adjustment_id}/reversal",
      headers: bearer_headers(other_token), params: { reason: "x" }
    assert_response :not_found
    assert_equal "adjustment_unavailable", JSON.parse(response.body).fetch("error")
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
