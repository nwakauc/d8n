require "test_helper"

class Api::V1::Hq::MfaControllerTest < ActionDispatch::IntegrationTest
  setup do
    @brand = Brand.create!(slug: "hq-mfa", name: "HQ MFA")
    BrandDomain.create!(brand: @brand, host: "hq-mfa.test")
    @user = User.create!
    BrandMembership.create!(brand: @brand, user: @user)
    IdentityIdentifier.create!(
      user: @user, kind: :email, normalized_value: "operator@example.test", verified_at: Time.current
    )
    @admin = AdminUser.create!(user: @user, status: :active)
    role = AdminRole.find_or_create_by!(name: "moderator")
    @assignment = AdminAssignment.create!(admin_user: @admin, brand: @brand, admin_role: role, status: :active)
    @token, @session = Session.issue!(brand: @brand, user: @user)
    host! "hq-mfa.test"
  end

  test "ordinary authentication exposes operator state but cannot reach sensitive HQ" do
    get "/api/v1/hq/operator", headers: headers(@token)
    assert_response :success
    assert_equal "not_enrolled", JSON.parse(response.body).dig("operator", "mfa", "state")
    assert_equal false, JSON.parse(response.body).dig("operator", "mfa", "verified")

    get "/api/v1/hq/trust_safety/overview", headers: headers(@token)
    assert_response :forbidden
    assert_equal "admin_mfa_required", JSON.parse(response.body).fetch("error")
  end

  test "enrollment confirmation returns recovery codes once and verifies this session" do
    post "/api/v1/hq/mfa/enrollment", headers: headers(@token)
    assert_response :created
    secret = JSON.parse(response.body).dig("mfa", "secret")
    assert JSON.parse(response.body).dig("mfa", "provisioning_uri").start_with?("otpauth://totp/")

    code = current_code(secret)
    assert_difference -> { SecurityEvent.where(event_type: "admin.mfa_enrollment_confirmed").count }, 1 do
      patch "/api/v1/hq/mfa/enrollment", headers: headers(@token), params: { code: }
    end
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal Admin::Mfa::RecoveryCodes::COUNT, body.fetch("recovery_codes").length
    assert @session.reload.admin_mfa_verified_for?(@admin)

    get "/api/v1/hq/trust_safety/overview", headers: headers(@token)
    assert_response :success
  end

  test "invalid challenge is audited and a valid TOTP verifies only that session" do
    credential = active_credential

    assert_difference -> { SecurityEvent.where(event_type: "admin.mfa_challenge_failed").count }, 1 do
      post "/api/v1/hq/mfa/challenge", headers: headers(@token), params: { code: invalid_code(credential.secret) }
    end
    assert_response :unprocessable_entity
    assert_equal "admin_mfa_code_invalid", JSON.parse(response.body).fetch("error")

    post "/api/v1/hq/mfa/challenge", headers: headers(@token), params: { code: current_code(credential.secret) }
    assert_response :success
    assert @session.reload.admin_mfa_verified_for?(@admin)
  end

  test "recovery code is consumed and cannot be reused" do
    code = Admin::Mfa::RecoveryCodes.generate.first
    active_credential.update!(recovery_code_digests: [ Admin::Mfa::RecoveryCodes.digest(code) ])

    post "/api/v1/hq/mfa/challenge", headers: headers(@token), params: { code: }
    assert_response :success

    second_token, = Session.issue!(brand: @brand, user: @user)
    post "/api/v1/hq/mfa/challenge", headers: headers(second_token), params: { code: }
    assert_response :unprocessable_entity
    assert_equal "admin_mfa_code_invalid", JSON.parse(response.body).fetch("error")
  end

  test "verified reset disables the credential and invalidates step-up" do
    credential = active_credential
    @session.update!(admin_mfa_credential: credential, admin_mfa_verified_at: Time.current)

    delete "/api/v1/hq/mfa/enrollment",
      headers: headers(@token), params: { code: current_code(credential.secret) }
    assert_response :success
    assert credential.reload.disabled?
    assert credential.deleted_at.present?
    assert_not @session.reload.admin_mfa_verified_for?(@admin)

    get "/api/v1/hq/trust_safety/overview", headers: headers(@token)
    assert_response :forbidden
    assert_equal "admin_mfa_required", JSON.parse(response.body).fetch("error")
  end

  test "revoked assignment cannot reach even operator or MFA endpoints" do
    @assignment.update!(status: :revoked)

    get "/api/v1/hq/operator", headers: headers(@token)
    assert_response :forbidden
    post "/api/v1/hq/mfa/enrollment", headers: headers(@token)
    assert_response :forbidden
  end

  private

  def active_credential
    AdminMfaCredential.create!(
      admin_user: @admin,
      status: :active,
      secret: Admin::Mfa::Totp.generate_secret,
      confirmed_at: Time.current,
      recovery_code_digests: []
    )
  end

  def current_code(secret)
    Admin::Mfa::Totp.code_at(secret:, counter: Time.current.to_i / Admin::Mfa::Totp::PERIOD)
  end

  def invalid_code(secret)
    current_code(secret) == "000000" ? "000001" : "000000"
  end

  def headers(token)
    { "Authorization" => "Bearer #{token}" }
  end
end
