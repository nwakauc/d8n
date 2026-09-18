require "test_helper"

class Api::V1::Date9jaBffAuthTest < ActionDispatch::IntegrationTest
  setup do
    @brand = Brand.create!(slug: "date9ja", name: "Date9ja", auth_methods: %w[email_password])
    BrandDomain.create!(brand: @brand, host: "date9ja-api.test")
    host! "date9ja-api.test"
    @origins = Rails.application.config.x.cors_origins
    Rails.application.config.x.cors_origins = [ "https://www.date9ja.love" ].freeze
  end

  teardown do
    Rails.application.config.x.cors_origins = @origins
  end

  %w[register login reactivation].each do |action|
    test "trusted BFF origin accepts #{action} and issues cookie session" do
      prepare_account(action)
      post "/api/v1/auth/password/#{action}", params: auth_params, headers: {
        "Origin" => "https://www.date9ja.love", "Sec-Fetch-Site" => "same-origin"
      }
      assert_response :created
      assert JSON.parse(response.body).dig("browser_session", "persisted")
      assert_includes response.headers.fetch("Set-Cookie"), "httponly"
      assert_nil JSON.parse(response.body)["token"]
    end

    test "foreign origin cannot perform browser #{action}" do
      prepare_account(action)
      assert_no_difference -> { Session.count } do
        post "/api/v1/auth/password/#{action}", params: auth_params, headers: {
          "Origin" => "https://attacker.example", "Sec-Fetch-Site" => "cross-site"
        }
      end
      assert_response :forbidden
      assert_equal "browser_session_origin_not_allowed", JSON.parse(response.body)["error"]
      assert_nil response.headers["Set-Cookie"]
    end
  end

  test "trusted BFF origin does not bypass session CSRF validation" do
    post "/api/v1/auth/password/register", params: auth_params, headers: { "Origin" => "https://www.date9ja.love" }
    assert_response :created
    token = JSON.parse(response.body).dig("browser_session", "csrf_token")
    delete "/api/v1/auth/session", headers: { "Origin" => "https://www.date9ja.love" }
    assert_response :forbidden
    assert_equal "csrf_token_invalid", JSON.parse(response.body)["error"]
    delete "/api/v1/auth/session", headers: {
      "Origin" => "https://www.date9ja.love", Identity::BrowserSession::CSRF_HEADER => token
    }
    assert_response :no_content
  end

  private

  def auth_params
    { identifier: "synthetic@example.com", password: "secret", session_mode: "browser" }
  end

  def prepare_account(action)
    return if action == "register"

    post "/api/v1/auth/password/register", params: auth_params.except(:session_mode)
    assert_response :created
    Accounts::DeactivateAccount.call(user: User.last, brand: @brand) if action == "reactivation"
  end
end
