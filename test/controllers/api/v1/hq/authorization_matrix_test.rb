require "test_helper"

class Api::V1::Hq::AuthorizationMatrixTest < ActionDispatch::IntegrationTest
  setup do
    @brand = Brand.create!(slug: "hq-rbac", name: "HQ RBAC")
    BrandDomain.create!(brand: @brand, host: "hq-rbac.test")
    Admin::Capabilities::ROLE_NAMES.each { |name| AdminRole.find_or_create_by!(name:) }
    @member = create_profile("Member")
    IdentityIdentifier.create!(
      user: @member.user, kind: :email, normalized_value: "member@example.test", verified_at: Time.current
    )
    @reporter = create_profile("Reporter")
    @report = Report.create!(
      brand: @brand,
      reporter_profile: @reporter,
      reported_profile: @member,
      reason: :spam,
      status: :open
    )
    host! "hq-rbac.test"
  end

  test "every canonical role is enforced by capabilities rather than its label" do
    expectations = {
      "founder" => %i[member trust discovery],
      "super_admin" => %i[member trust discovery],
      "operations" => %i[member trust discovery],
      "trust_safety" => %i[member trust],
      "support" => %i[member discovery],
      "engineering" => %i[discovery],
      "marketing" => [],
      "analyst" => [],
      "moderator" => %i[member trust discovery]
    }

    expectations.each do |role, allowed|
      token = token_for(role)
      assert_access allowed.include?(:member), token, "/api/v1/hq/members/member@example.test", role
      assert_access allowed.include?(:trust), token, "/api/v1/hq/trust_safety/overview", role
      assert_access allowed.include?(:discovery), token,
        "/api/v1/hq/members/member@example.test/discovery_diagnostic", role
    end
  end

  test "report mutation requires the moderate capability" do
    support_token = token_for("support")
    patch "/api/v1/admin/reports/#{@report.id}", headers: headers(support_token),
      params: { status: "dismissed" }
    assert_response :forbidden
    assert @report.reload.status_open?

    trust_token = token_for("trust_safety")
    patch "/api/v1/admin/reports/#{@report.id}", headers: headers(trust_token),
      params: { status: "dismissed" }
    assert_response :success
    assert @report.reload.status_dismissed?
  end

  private

  def assert_access(expected, token, path, role)
    get path, headers: headers(token)
    if expected
      assert_response :success, "expected #{role} to access #{path}"
    else
      assert_response :forbidden, "expected #{role} to be denied #{path}"
      assert_equal "forbidden", JSON.parse(response.body).fetch("error")
    end
  end

  def token_for(role_name)
    user = User.create!
    BrandMembership.create!(brand: @brand, user:)
    admin = AdminUser.create!(user:, status: :active)
    AdminAssignment.create!(
      admin_user: admin,
      brand: @brand,
      admin_role: AdminRole.find_by!(name: role_name),
      status: :active
    )
    issue_mfa_verified_admin_session!(user:, brand: @brand, admin_user: admin)
  end

  def create_profile(display_name)
    user = User.create!
    membership = BrandMembership.create!(brand: @brand, user:)
    Profile.create!(
      brand: @brand,
      user:,
      brand_membership: membership,
      display_name:,
      birthdate: 30.years.ago.to_date,
      gender: "person",
      status: :active,
      visibility: :visible
    )
  end

  def headers(token)
    { "Authorization" => "Bearer #{token}" }
  end
end
