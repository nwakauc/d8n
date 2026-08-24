require "test_helper"

class Api::V1::BrowserSessionTest < ActionDispatch::IntegrationTest
  setup do
    @brand = Brand.create!(
      slug: "dateza",
      name: "DateZA",
      auth_methods: %w[ email_password ]
    )
    BrandDomain.create!(brand: @brand, host: "dateza.test")
    host! "dateza.test"
  end

  test "registration establishes an HttpOnly persistent browser session" do
    register

    assert_response :created
    body = JSON.parse(response.body)
    cookie = response.headers.fetch("Set-Cookie")
    assert_equal true, body.dig("browser_session", "persisted")
    assert body.dig("browser_session", "csrf_token").present?
    assert_nil body["token"]
    assert_includes cookie, "#{Identity::BrowserSession::COOKIE_NAME}="
    assert_includes cookie, "httponly"
    assert_includes cookie, "path=/api/v1"
    assert_includes cookie, "samesite=lax"
    refute_includes cookie, "domain="
  end

  test "login establishes the same persistent browser session mechanism" do
    register
    cookies.delete(Identity::BrowserSession::COOKIE_NAME)

    post "/api/v1/auth/password/login", params: login_params

    assert_response :created
    assert_equal true, JSON.parse(response.body).dig("browser_session", "persisted")
    assert_includes response.headers.fetch("Set-Cookie"), Identity::BrowserSession::COOKIE_NAME
  end

  test "bearer mode remains the default and does not set a browser cookie" do
    post "/api/v1/auth/password/register", params: {
      identifier: "member@example.com",
      password: "secret"
    }

    assert_response :created
    body = JSON.parse(response.body)
    assert body.fetch("token").present?
    assert_equal "Bearer", body.fetch("token_type")
    assert_nil body["browser_session"]
    assert_nil response.headers["Set-Cookie"]
  end

  test "an unknown session mode fails instead of returning an unexpected bearer secret" do
    assert_no_difference -> { Session.count } do
      post "/api/v1/auth/password/register", params: {
        identifier: "member@example.com",
        password: "secret",
        session_mode: "persistent"
      }
    end

    assert_response :unprocessable_entity
    assert_equal({ "error" => "invalid_session_mode" }, JSON.parse(response.body))
  end

  test "a new browser login rotates the browser credential" do
    register
    original_cookie = cookies[Identity::BrowserSession::COOKIE_NAME]

    post "/api/v1/auth/password/login", params: login_params

    assert_response :created
    refute_equal original_cookie, cookies[Identity::BrowserSession::COOKIE_NAME]
    assert_equal 2, Session.where(brand: @brand, user: User.last).count
  end

  test "me bootstraps authentication from the browser cookie without a bearer header" do
    register

    get "/api/v1/me"

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal User.last.id, body.fetch("user_id")
    assert_equal "dateza", body.dig("brand", "slug")
    assert_equal "cookie", body.dig("session", "authentication_mode")
    assert body.dig("session", "csrf_token").present?
  end

  test "cookie authenticated mutations require the session CSRF token" do
    register
    session = Session.last

    delete "/api/v1/auth/session"

    assert_response :forbidden
    assert_equal({ "error" => "csrf_token_invalid" }, JSON.parse(response.body))
    assert_not session.reload.revoked?
  end

  test "a CSRF token from another session is rejected" do
    register
    _, other_session = Session.issue!(user: User.last, brand: @brand)

    delete "/api/v1/auth/session", headers: csrf_headers(
      Identity::BrowserSession.csrf_token(session: other_session)
    )

    assert_response :forbidden
    assert_not Session.order(:id).first.reload.revoked?
  end

  test "logout with CSRF revokes the server session and clears the browser cookie" do
    register
    body = JSON.parse(response.body)
    raw_token = cookies[Identity::BrowserSession::COOKIE_NAME]
    csrf_token = body.dig("browser_session", "csrf_token")
    session = Session.last

    delete "/api/v1/auth/session", headers: csrf_headers(csrf_token)

    assert_response :no_content
    assert session.reload.revoked?
    assert_includes response.headers.fetch("Set-Cookie"), "#{Identity::BrowserSession::COOKIE_NAME}="
    assert_includes response.headers.fetch("Set-Cookie"), "max-age=0"

    cookies[Identity::BrowserSession::COOKIE_NAME] = raw_token
    get "/api/v1/me"
    assert_response :unauthorized
    assert_equal({ "error" => "session_revoked" }, JSON.parse(response.body))
  end

  test "expired browser sessions fail bootstrap with a stable error and are cleared" do
    register
    Session.last.update!(expires_at: 1.minute.ago)

    get "/api/v1/me"

    assert_response :unauthorized
    assert_equal({ "error" => "session_expired" }, JSON.parse(response.body))
    assert_includes response.headers.fetch("Set-Cookie"), "max-age=0"
  end

  test "malformed browser credentials fail closed without revealing details" do
    cookies[Identity::BrowserSession::COOKIE_NAME] = "malformed"

    get "/api/v1/me"

    assert_response :unauthorized
    assert_equal({ "error" => "unauthorized" }, JSON.parse(response.body))
  end

  test "a DateZA browser credential cannot authenticate on HookUs" do
    register
    raw_token = cookies[Identity::BrowserSession::COOKIE_NAME]
    hookus = Brand.create!(slug: "hookus", name: "HookUs")
    BrandDomain.create!(brand: hookus, host: "hookus.test")
    BrandMembership.create!(brand: hookus, user: User.last)
    cookies.delete(Identity::BrowserSession::COOKIE_NAME)
    host! "hookus.test"

    get "/api/v1/me", headers: {
      "Cookie" => "#{Identity::BrowserSession::COOKIE_NAME}=#{raw_token}"
    }

    assert_response :unauthorized
    assert_equal({ "error" => "unauthorized" }, JSON.parse(response.body))
  end

  test "inactive brand membership invalidates browser authentication" do
    register
    BrandMembership.find_by!(brand: @brand, user: User.last).update!(status: :left)

    get "/api/v1/me"

    assert_response :unauthorized
    assert_equal({ "error" => "unauthorized" }, JSON.parse(response.body))
  end

  test "brand account closure through the browser session revokes and clears it" do
    register
    csrf_token = JSON.parse(response.body).dig("browser_session", "csrf_token")
    session = Session.last

    delete "/api/v1/me",
      headers: csrf_headers(csrf_token),
      params: { confirmation: "close" }

    assert_response :success
    assert session.reload.revoked?
    assert BrandMembership.find_by!(brand: @brand, user: User.last).left?
    assert_includes response.headers.fetch("Set-Cookie"), "max-age=0"
  end

  test "an explicit bearer credential takes precedence and remains CSRF exempt" do
    register
    valid_bearer, = Session.issue!(user: User.last, brand: @brand)

    get "/api/v1/me", headers: { "Authorization" => "Bearer invalid" }
    assert_response :unauthorized

    delete "/api/v1/auth/session", headers: bearer_headers(valid_bearer)
    assert_response :no_content
  end

  test "an unapproved cross-site origin cannot establish a browser credential" do
    assert_no_difference -> { Session.count } do
      register(headers: { "Origin" => "https://attacker.example" })
    end

    assert_response :forbidden
    assert_equal({ "error" => "browser_session_origin_not_allowed" }, JSON.parse(response.body))
    assert_nil response.headers["Set-Cookie"]
  end

  test "cross-site fetch metadata cannot establish a browser credential without Origin" do
    assert_no_difference -> { Session.count } do
      register(headers: { "Sec-Fetch-Site" => "cross-site" })
    end

    assert_response :forbidden
    assert_equal({ "error" => "browser_session_origin_not_allowed" }, JSON.parse(response.body))
  end

  test "an approved credentialed origin can establish a browser credential" do
    register(headers: { "Origin" => "http://localhost:5173" })

    assert_response :created
    assert_equal true, JSON.parse(response.body).dig("browser_session", "persisted")
    assert_equal "true", response.headers["Access-Control-Allow-Credentials"]
  end

  test "an unconfigured brand fails closed for browser session mode" do
    unsupported = Brand.create!(slug: "date9ja", name: "Date9ja", auth_methods: %w[email_password])
    BrandDomain.create!(brand: unsupported, host: "date9ja.test")
    host! "date9ja.test"

    assert_no_difference -> { Session.count } do
      register
    end

    assert_response :not_found
    assert_equal({ "error" => "browser_session_not_configured" }, JSON.parse(response.body))
  end

  private

  def register(headers: {})
    post "/api/v1/auth/password/register", headers:, params: {
      identifier: "member@example.com",
      password: "secret",
      device_name: "Web",
      session_mode: "browser"
    }
  end

  def login_params
    { identifier: "member@example.com", password: "secret", device_name: "Web", session_mode: "browser" }
  end

  def csrf_headers(token)
    { Identity::BrowserSession::CSRF_HEADER => token }
  end

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end
end
