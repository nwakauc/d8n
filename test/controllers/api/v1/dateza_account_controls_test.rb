require "test_helper"

# Proves password change, deactivation, and reactivation are genuinely shared
# D8N ID infrastructure — the same Identity::PasswordChange, Accounts::
# DeactivateAccount, and Identity::AccountReactivation used by HookUs, reachable
# through the same routes, on a brand with none of DateZA's own controllers or
# services involved.
class DatezaAccountControlsTest < ActionDispatch::IntegrationTest
  setup do
    @brand = Brand.create!(
      slug: "dateza", name: "DateZA", auth_methods: %w[phone_password email_password]
    )
    BrandDomain.create!(brand: @brand, host: "dateza.test")
    host! "dateza.test"
  end

  test "account_controls reports all three D8N ID capabilities enabled for DateZA" do
    post "/api/v1/auth/password/register", params: { identifier: "+27 82 555 1234", password: "secret" }
    assert_response :created
    token = JSON.parse(response.body).fetch("token")

    get "/api/v1/me", headers: bearer_headers(token)
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "active", body.fetch("account_status")
    assert_equal(
      { "password_change" => true, "deactivation" => true, "deletion" => true },
      body.fetch("account_controls")
    )
  end

  test "a DateZA member deactivates and reactivates through the same shared endpoints as HookUs" do
    post "/api/v1/auth/password/register", params: { identifier: "+27 82 555 1234", password: "secret" }
    assert_response :created
    token = JSON.parse(response.body).fetch("token")
    user = Session.last.user

    post "/api/v1/account/deactivation", headers: bearer_headers(token), params: { confirmation: "deactivate" }
    assert_response :success
    assert user.brand_memberships.find_by(brand: @brand).deactivated?

    get "/api/v1/me", headers: bearer_headers(token)
    assert_response :unauthorized

    post "/api/v1/auth/password/login", params: { identifier: "+27 82 555 1234", password: "secret" }
    assert_response :conflict
    assert_equal "account_deactivated", JSON.parse(response.body).fetch("error")

    post "/api/v1/auth/password/reactivation", params: { identifier: "+27 82 555 1234", password: "secret" }
    assert_response :created
    new_token = JSON.parse(response.body).fetch("token")
    assert user.brand_memberships.find_by(brand: @brand).active?

    get "/api/v1/me", headers: bearer_headers(new_token)
    assert_response :success
  end

  test "a DateZA member changes their password through the shared endpoint" do
    post "/api/v1/auth/password/register", params: { identifier: "+27 82 555 1234", password: "secret" }
    assert_response :created
    token = JSON.parse(response.body).fetch("token")
    credential = Session.last.credential

    patch "/api/v1/auth/password",
      headers: bearer_headers(token),
      params: { current_password: "secret", password: "new-secret", password_confirmation: "new-secret" }

    assert_response :success
    assert Identity::PasswordEngine.matches?(credential:, password: "new-secret")
  end

  private

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end
end
