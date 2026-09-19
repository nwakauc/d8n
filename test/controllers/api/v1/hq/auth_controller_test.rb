require "test_helper"

class Api::V1::Hq::AuthControllerTest < ActionDispatch::IntegrationTest
  setup do
    @brand = Brand.create!(slug: "hq-auth", name: "HQ Auth")
    BrandDomain.create!(brand: @brand, host: "hq-auth.test")
    @user = User.create!
    BrandMembership.create!(brand: @brand, user: @user, status: :active)
    identifier = IdentityIdentifier.create!(
      user: @user, brand: @brand, kind: :email,
      normalized_value: "operator@example.test", verified_at: Time.current
    )
    credential = Credential.create!(user: @user, identity_identifier: identifier, kind: :password, status: :active)
    Identity::PasswordEngine.set!(credential:, password: "secret")
    @admin_user = AdminUser.create!(user: @user, status: :active)
    role = AdminRole.find_or_create_by!(name: "founder")
    AdminAssignment.create!(admin_user: @admin_user, brand: @brand, admin_role: role, status: :active)
    host! "hq-auth.test"
  end

  test "logs in an HQ operator with a browser session" do
    post "/api/v1/hq/auth/login", params: {
      identifier: "operator@example.test", password: "secret", device_name: "D8N HQ"
    }

    assert_response :created
    body = JSON.parse(response.body)
    assert_equal @user.id, body.dig("operator", "user_id")
    assert_equal @admin_user.id, body.dig("operator", "admin_user_id")
    assert response.headers["Set-Cookie"].include?(Identity::HqBrowserSession::COOKIE_NAME)
  end
end
