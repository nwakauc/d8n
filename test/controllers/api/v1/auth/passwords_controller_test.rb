require "test_helper"

class Api::V1::Auth::PasswordsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @brand = Brand.create!(
      slug: "hookus",
      name: "HookUs",
      auth_methods: %w[ phone_password email_password ]
    )
    BrandDomain.create!(brand: @brand, host: "hookus.test")
    host! "hookus.test"
  end

  test "registers with phone and immediately issues a brand session" do
    assert_difference -> { User.count }, 1 do
      assert_difference -> { IdentityIdentifier.phone.count }, 1 do
        assert_difference -> { Credential.password.count }, 1 do
          assert_difference -> { BrandMembership.where(brand: @brand).count }, 1 do
            assert_difference -> { Session.where(brand: @brand).count }, 1 do
              post "/api/v1/auth/password/register", params: phone_registration
            end
          end
        end
      end
    end

    assert_response :created
    body = JSON.parse(response.body)
    identifier = IdentityIdentifier.last
    credential = Credential.password.last

    assert_equal "27821234567", identifier.normalized_value
    assert_nil identifier.verified_at
    assert_nil credential.verified_at
    assert Identity::PasswordEngine.matches?(credential:, password: "secret")
    assert_equal({ "kind" => "phone", "verified" => false }, body.fetch("identifier"))
    assert_equal "hookus", body.fetch("brand").fetch("slug")
    assert body.fetch("token").present?
  end

  test "registers with a normalized email without pretending it is verified" do
    post "/api/v1/auth/password/register",
      params: { identifier: " ADA@Example.COM ", password: "secret", device_name: "Web" }

    assert_response :created
    identifier = IdentityIdentifier.last
    assert identifier.email?
    assert_equal "ada@example.com", identifier.normalized_value
    assert_nil identifier.verified_at
    assert_equal({ "kind" => "email", "verified" => false }, JSON.parse(response.body).fetch("identifier"))
  end

  test "logs in with an unverified phone and password" do
    register_phone
    delete "/api/v1/auth/session", headers: bearer_headers(JSON.parse(response.body).fetch("token"))

    assert_difference -> { Session.where(brand: @brand).count }, 1 do
      post "/api/v1/auth/password/login",
        params: { identifier: "+27 82 123 4567", password: "secret", device_name: "Returning Web" }
    end

    assert_response :created
    assert_equal false, JSON.parse(response.body).fetch("identifier").fetch("verified")
    assert_equal "Returning Web", Session.last.device_name
  end

  test "logs in with a normalized email and password" do
    post "/api/v1/auth/password/register", params: { identifier: "ada@example.com", password: "secret" }

    post "/api/v1/auth/password/login", params: { identifier: " ADA@EXAMPLE.COM ", password: "secret" }

    assert_response :created
    assert_equal "email", JSON.parse(response.body).fetch("identifier").fetch("kind")
  end

  test "rejects short passwords without leaving partial account records" do
    assert_no_difference -> { User.count } do
      assert_no_difference -> { IdentityIdentifier.count } do
        post "/api/v1/auth/password/register",
          params: { identifier: "+27 82 123 4567", password: "12345" }
      end
    end

    assert_response :unprocessable_entity
    assert_equal({ "error" => "registration_unavailable" }, JSON.parse(response.body))
  end

  test "returns the same registration error for malformed and occupied identifiers" do
    register_phone

    post "/api/v1/auth/password/register", params: phone_registration
    occupied_response = response.body
    post "/api/v1/auth/password/register", params: { identifier: "invalid@", password: "secret" }

    assert_response :unprocessable_entity
    assert_equal occupied_response, response.body
    assert_equal({ "error" => "registration_unavailable" }, JSON.parse(response.body))
  end

  test "does not let authenticated registration create an accidental second account" do
    register_phone
    token = JSON.parse(response.body).fetch("token")

    assert_no_difference -> { User.count } do
      post "/api/v1/auth/password/register",
        headers: bearer_headers(token),
        params: { identifier: "other@example.com", password: "secret" }
    end

    assert_response :conflict
    assert_equal({ "error" => "already_authenticated" }, JSON.parse(response.body))
  end

  test "returns generic login failure for unknown identifier and wrong password" do
    register_phone

    post "/api/v1/auth/password/login", params: { identifier: "+27 82 123 4567", password: "wrong-password" }
    wrong_password_response = response.body
    post "/api/v1/auth/password/login", params: { identifier: "+27 82 999 9999", password: "wrong-password" }

    assert_response :unauthorized
    assert_equal wrong_password_response, response.body
    assert_equal({ "error" => "invalid_credentials" }, JSON.parse(response.body))
  end

  test "does not implicitly join an existing identity to another brand" do
    register_phone
    other_brand = Brand.create!(
      slug: "date9ja",
      name: "Date9ja",
      auth_methods: %w[ phone_password email_password ]
    )
    BrandDomain.create!(brand: other_brand, host: "date9ja.test")
    host! "date9ja.test"

    assert_no_difference -> { BrandMembership.where(brand: other_brand).count } do
      post "/api/v1/auth/password/login",
        params: { identifier: "+27 82 123 4567", password: "secret" }
    end

    assert_response :unauthorized
    assert_equal({ "error" => "invalid_credentials" }, JSON.parse(response.body))
  end

  test "enforces the resolved brand method policy" do
    @brand.update!(auth_methods: %w[ email_password ])

    post "/api/v1/auth/password/register", params: phone_registration

    assert_response :not_found
    assert_equal({ "error" => "auth_method_unavailable" }, JSON.parse(response.body))
  end

  test "requires a resolved brand" do
    host! "unknown.test"

    post "/api/v1/auth/password/register", params: phone_registration

    assert_response :not_found
    assert_equal({ "error" => "brand_required" }, JSON.parse(response.body))
  end

  test "audits successful registration and failed login without password content" do
    register_phone
    post "/api/v1/auth/password/login", params: { identifier: "+27 82 123 4567", password: "wrong-password" }

    registration = SecurityEvent.find_by!(event_type: "auth.password_registration.succeeded")
    failed_login = SecurityEvent.find_by!(event_type: "auth.password_login.failed")
    assert_equal "phone", registration.metadata.fetch("identifier_kind")
    assert_equal "4567", failed_login.metadata.fetch("identifier_last4")
    assert_not_includes registration.metadata.to_json, "secret"
    assert_not_includes failed_login.metadata.to_json, "wrong-password"
  end

  test "rate limits repeated password login failures" do
    register_phone
    10.times do
      AuthAttempt.create!(
        brand: @brand,
        kind: :password,
        result: :failed,
        identifier: "27821234567",
        ip_address: "127.0.0.1",
        metadata: { purpose: "password_login" }
      )
    end

    assert_no_difference -> { Session.count } do
      post "/api/v1/auth/password/login",
        params: { identifier: "+27 82 123 4567", password: "secret" }
    end

    assert_response :too_many_requests
    assert_equal({ "error" => "rate_limited" }, JSON.parse(response.body))
    assert response.headers.fetch("Retry-After").to_i.positive?
  end

  test "denies login when the user lifecycle becomes inactive" do
    register_phone
    User.last.update!(status: :suspended)

    assert_no_difference -> { Session.count } do
      post "/api/v1/auth/password/login",
        params: { identifier: "+27 82 123 4567", password: "secret" }
    end

    assert_response :unauthorized
    assert_equal({ "error" => "invalid_credentials" }, JSON.parse(response.body))
  end

  private

  def phone_registration
    { identifier: "+27 82 123 4567", password: "secret", device_name: "Web" }
  end

  def register_phone
    post "/api/v1/auth/password/register", params: phone_registration
    assert_response :created
  end

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end
end
