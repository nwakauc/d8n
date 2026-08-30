require "test_helper"

class Api::V1::Hq::OperatorsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @brand = Brand.create!(slug: "hq-operators", name: "HQ Operators")
    BrandDomain.create!(brand: @brand, host: "hq-operators.test")
    seed_roles
    @founder, @founder_token = create_operator(role: "founder", email: "founder@example.test")
    host! "hq-operators.test"
  end

  test "founder assigns an existing brand member and the server returns capabilities" do
    target = User.create!
    BrandMembership.create!(brand: @brand, user: target)
    IdentityIdentifier.create!(
      user: target, kind: :email, normalized_value: "support@example.test", verified_at: Time.current
    )

    assert_difference -> { SecurityEvent.where(event_type: "admin.operator_assigned").count }, 1 do
      post "/api/v1/hq/operators", headers: headers(@founder_token),
        params: { email: "support@example.test", role: "support" }
    end
    assert_response :created
    operator = JSON.parse(response.body).fetch("operator")
    assert_equal "support", operator.fetch("role")
    assert_includes operator.fetch("effective_capabilities"), Admin::Capabilities::MEMBER_SENSITIVE_READ
    assert_not_includes operator.fetch("effective_capabilities"), Admin::Capabilities::REPORTS_MODERATE
    assert_not_includes response.body, "credential"
  end

  test "founder cannot self-modify and founder role cannot be assigned through the API" do
    patch "/api/v1/hq/operators/#{@founder.id}", headers: headers(@founder_token),
      params: { role: "support" }
    assert_response :unprocessable_entity
    assert_equal "operator_management_forbidden", JSON.parse(response.body).fetch("error")

    target = existing_member("target@example.test")
    post "/api/v1/hq/operators", headers: headers(@founder_token),
      params: { email: target, role: "founder" }
    assert_response :unprocessable_entity
    assert_equal "invalid_role", JSON.parse(response.body).fetch("error")
  end

  test "super admin cannot create or modify another super admin" do
    super_admin, token = create_operator(role: "super_admin", email: "super@example.test")
    peer, = create_operator(role: "super_admin", email: "peer@example.test")

    patch "/api/v1/hq/operators/#{peer.id}", headers: headers(token), params: { status: "revoked" }
    assert_response :unprocessable_entity
    assert_equal "operator_management_forbidden", JSON.parse(response.body).fetch("error")

    target_email = existing_member("candidate@example.test")
    post "/api/v1/hq/operators", headers: headers(token), params: { email: target_email, role: "super_admin" }
    assert_response :unprocessable_entity
    assert_equal "invalid_role", JSON.parse(response.body).fetch("error")
    assert super_admin.active?
  end

  test "revocation immediately removes current-brand authorization" do
    support, support_token = create_operator(role: "support", email: "revoked@example.test")

    patch "/api/v1/hq/operators/#{support.id}", headers: headers(@founder_token), params: { status: "revoked" }
    assert_response :success

    get "/api/v1/hq/operator", headers: headers(support_token)
    assert_response :forbidden
  end

  test "operator management is tenant isolated" do
    other = Brand.create!(slug: "hq-operators-other", name: "Other")
    other_admin, = create_operator(role: "support", email: "other@example.test", brand: other)

    patch "/api/v1/hq/operators/#{other_admin.id}", headers: headers(@founder_token), params: { status: "revoked" }
    assert_response :not_found
    assert AdminAssignment.kept.active.exists?(admin_user: other_admin, brand: other)
  end

  test "roles without operator capabilities cannot enumerate operators" do
    trust_admin, token = create_operator(role: "trust_safety", email: "trust@example.test")

    get "/api/v1/hq/operators", headers: headers(token)
    assert_response :forbidden
    assert trust_admin.active?
  end

  private

  def seed_roles
    Admin::Capabilities::ROLE_NAMES.each { |name| AdminRole.find_or_create_by!(name:) }
  end

  def existing_member(email)
    user = User.create!
    BrandMembership.create!(brand: @brand, user:)
    IdentityIdentifier.create!(user:, kind: :email, normalized_value: email, verified_at: Time.current)
    email
  end

  def create_operator(role:, email:, brand: @brand)
    user = User.create!
    BrandMembership.create!(brand:, user:)
    IdentityIdentifier.create!(user:, kind: :email, normalized_value: email, verified_at: Time.current)
    admin = AdminUser.create!(user:, status: :active)
    assignment = AdminAssignment.create!(
      admin_user: admin, brand:, admin_role: AdminRole.find_by!(name: role), status: :active
    )
    token = issue_mfa_verified_admin_session!(user:, brand:, admin_user: admin)
    [ admin, token, assignment ]
  end

  def headers(token)
    { "Authorization" => "Bearer #{token}" }
  end
end
