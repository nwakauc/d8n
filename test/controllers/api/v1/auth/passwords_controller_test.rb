require "test_helper"

class Api::V1::Auth::PasswordsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

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
    assert_equal "phone", body.dig("identifier", "kind")
    assert_equal false, body.dig("identifier", "verified")
    assert_equal "••••••••567", body.dig("identifier", "masked_destination")
    assert_equal true, body.fetch("verification_required")
    assert_equal "phone", body.fetch("verification_channel")
    assert_equal true, body.dig("verification", "code_dispatched")
    assert_in_delta 60, body.dig("verification", "resend_available_in"), 1
    assert_equal OtpChallenge.phone_verification.last.expires_at.iso8601, body.dig("verification", "expires_at")
    assert_equal "hookus", body.fetch("brand").fetch("slug")
    assert body.fetch("token").present?
    assert_nil body["browser_session"]
    assert_nil response.headers["Set-Cookie"]
    assert_equal "profile_required", body.fetch("onboarding").fetch("state")
    assert_equal "profile", body.fetch("onboarding").fetch("next_step")
  end

  test "registers with a normalized email without pretending it is verified" do
    post "/api/v1/auth/password/register",
      params: { identifier: " ADA@Example.COM ", password: "secret", device_name: "Web" }

    assert_response :created
    identifier = IdentityIdentifier.last
    assert identifier.email?
    assert_equal "ada@example.com", identifier.normalized_value
    assert_nil identifier.verified_at
    body = JSON.parse(response.body)
    assert_equal false, body.dig("identifier", "verified")
    assert_equal "a•••@example.com", body.dig("identifier", "masked_destination")
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

  test "international input finds one legacy national-form identity without creating a duplicate" do
    user = User.create!
    identifier = user.identity_identifiers.create!(kind: :phone, normalized_value: "0821234567")
    credential = user.credentials.create!(identity_identifier: identifier, kind: :password, status: :active)
    Identity::PasswordEngine.set!(credential:, password: "secret")
    BrandMembership.create!(brand: @brand, user:, status: :active)

    post "/api/v1/auth/password/login",
      params: { identifier: "+27821234567", password: "secret", device_name: "Returning Web" }

    assert_response :created
    assert_equal user.id, JSON.parse(response.body).fetch("user_id")

    assert_no_difference -> { User.count } do
      post "/api/v1/auth/password/register",
        params: { identifier: "+27821234567", password: "secret", device_name: "Web" }
    end
    assert_response :unprocessable_entity
    assert_equal 1, IdentityIdentifier.phone.where(normalized_value: %w[0821234567 27821234567]).count
  end

  test "logs in with a normalized email and password" do
    post "/api/v1/auth/password/register", params: { identifier: "ada@example.com", password: "secret" }

    post "/api/v1/auth/password/login", params: { identifier: " ADA@EXAMPLE.COM ", password: "secret" }

    assert_response :created
    assert_equal "email", JSON.parse(response.body).fetch("identifier").fetch("kind")
  end

  test "returns resumable current-brand onboarding state on login" do
    register_phone
    user = IdentityIdentifier.last.user
    membership = BrandMembership.find_by!(user:, brand: @brand)
    Profile.create!(
      user:,
      brand: @brand,
      brand_membership: membership,
      display_name: "Ada",
      birthdate: 25.years.ago.to_date,
      gender: "woman"
    )

    post "/api/v1/auth/password/login", params: phone_registration

    assert_response :created
    onboarding = JSON.parse(response.body).fetch("onboarding")
    assert_equal "profile_incomplete", onboarding.fetch("state")
    assert_equal "preferences", onboarding.fetch("next_step")
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

  test "rate limits many distinct SUCCESSFUL registrations from one IP, creating no partial state" do
    Identity::PasswordThrottle::POLICIES.fetch("password_registration").fetch(:ip_limit).times do |index|
      post "/api/v1/auth/password/register",
        params: { identifier: "ip-flood-#{index}@example.com", password: "secret", device_name: "Bot" }
      assert_response :created
    end

    assert_no_difference [
      -> { User.count }, -> { IdentityIdentifier.count }, -> { Credential.count },
      -> { BrandMembership.where(brand: @brand).count }, -> { Session.where(brand: @brand).count }
    ] do
      assert_no_enqueued_jobs only: Notifications::DeliverChallengeJob do
        post "/api/v1/auth/password/register",
          params: { identifier: "one-more@example.com", password: "secret", device_name: "Bot" }
      end
    end

    assert_response :too_many_requests
    assert_equal({ "error" => "rate_limited" }, JSON.parse(response.body))
    assert response.headers.fetch("Retry-After").to_i.positive?
  end

  test "the registration IP throttle is platform-wide: switching brand host does not reset it" do
    other_brand = Brand.create!(slug: "dateza", name: "DateZA", auth_methods: %w[ email_password ])
    BrandDomain.create!(brand: other_brand, host: "dateza.test")
    ip_limit = Identity::PasswordThrottle::POLICIES.fetch("password_registration").fetch(:ip_limit)

    (ip_limit - 1).times do |index|
      post "/api/v1/auth/password/register",
        params: { identifier: "split-#{index}@example.com", password: "secret" }
      assert_response :created
    end

    host! "dateza.test"
    post "/api/v1/auth/password/register", params: { identifier: "split-last@example.com", password: "secret" }
    assert_response :created

    post "/api/v1/auth/password/register", params: { identifier: "one-more-still@example.com", password: "secret" }
    assert_response :too_many_requests
  end

  test "the registration identifier throttle is platform-wide: switching brand host does not reset it" do
    other_brand = Brand.create!(slug: "dateza", name: "DateZA", auth_methods: %w[ email_password ])
    BrandDomain.create!(brand: other_brand, host: "dateza.test")
    identifier_limit = Identity::PasswordThrottle::POLICIES.fetch("password_registration").fetch(:identifier_limit)
    remote_ips = (1..(identifier_limit + 1)).map { |n| "203.0.113.#{n}" }

    # First attempt succeeds and claims the identifier; every attempt after that
    # against the SAME already-registered identifier fails with 422 — each still
    # counts toward the identifier throttle, spread across different source IPs
    # so only the identifier scope (never the much higher ip_limit) can trip.
    post "/api/v1/auth/password/register",
      params: { identifier: "taken@example.com", password: "secret" },
      headers: { "REMOTE_ADDR" => remote_ips[0] }
    assert_response :created

    (identifier_limit - 1).times do |index|
      post "/api/v1/auth/password/register",
        params: { identifier: "taken@example.com", password: "secret" },
        headers: { "REMOTE_ADDR" => remote_ips[index + 1] }
      assert_response :unprocessable_entity
    end

    host! "dateza.test"
    post "/api/v1/auth/password/register",
      params: { identifier: "taken@example.com", password: "secret" },
      headers: { "REMOTE_ADDR" => remote_ips.last }

    assert_response :too_many_requests
    assert_equal({ "error" => "rate_limited" }, JSON.parse(response.body))
  end

  test "malformed identifiers cannot bypass the registration IP throttle" do
    ip_limit = Identity::PasswordThrottle::POLICIES.fetch("password_registration").fetch(:ip_limit)

    ip_limit.times do
      post "/api/v1/auth/password/register", params: { identifier: "not-an-email-or-phone", password: "secret" }
      assert_response :unprocessable_entity
      assert_equal({ "error" => "registration_unavailable" }, JSON.parse(response.body))
    end

    assert_no_difference -> { User.count } do
      post "/api/v1/auth/password/register", params: { identifier: "still-not-valid", password: "secret" }
    end

    assert_response :too_many_requests
    assert_equal({ "error" => "rate_limited" }, JSON.parse(response.body))
    assert_equal "throttled", AuthAttempt.where(brand: @brand).order(:created_at).last.result
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

  test "changes the authenticated password and revokes other sessions for that credential" do
    register_phone
    body = JSON.parse(response.body)
    current_token = body.fetch("token")
    current_session = Session.last
    credential = current_session.credential
    _, other_session = Session.issue!(user: current_session.user, brand: @brand, credential:)

    patch "/api/v1/auth/password",
      headers: bearer_headers(current_token),
      params: {
        current_password: "secret",
        password: "new-secret",
        password_confirmation: "new-secret"
      }

    assert_response :success
    assert_equal({ "message" => "Password updated." }, JSON.parse(response.body))
    assert Identity::PasswordEngine.matches?(credential:, password: "new-secret")
    assert_not Identity::PasswordEngine.matches?(credential:, password: "secret")
    assert_not current_session.reload.revoked?
    assert other_session.reload.revoked?

    event = SecurityEvent.find_by!(event_type: "auth.password_change.succeeded", user: current_session.user)
    assert_equal 1, event.metadata.fetch("revoked_session_count")
    assert_not_includes event.metadata.to_json, "new-secret"
    assert_not_includes event.metadata.to_json, "secret"
  end

  test "requires the current password and leaves the credential unchanged on failure" do
    register_phone
    token = JSON.parse(response.body).fetch("token")
    credential = Session.last.credential

    patch "/api/v1/auth/password",
      headers: bearer_headers(token),
      params: {
        current_password: "wrong-password",
        password: "new-secret",
        password_confirmation: "new-secret"
      }

    assert_response :unauthorized
    assert_equal({ "error" => "invalid_current_password" }, JSON.parse(response.body))
    assert Identity::PasswordEngine.matches?(credential:, password: "secret")
  end

  test "rejects mismatched short and unchanged replacement passwords" do
    register_phone
    token = JSON.parse(response.body).fetch("token")

    [
      [ "new-secret", "different", "invalid_password" ],
      [ "short", "short", "invalid_password" ],
      [ "secret", "secret", "password_unchanged" ]
    ].each do |password, confirmation, error|
      patch "/api/v1/auth/password",
        headers: bearer_headers(token),
        params: {
          current_password: "secret",
          password:,
          password_confirmation: confirmation
        }

      assert_response :unprocessable_entity
      assert_equal({ "error" => error }, JSON.parse(response.body))
    end
  end

  test "requires an authenticated password-backed session" do
    patch "/api/v1/auth/password",
      params: { current_password: "secret", password: "new-secret", password_confirmation: "new-secret" }
    assert_response :unauthorized

    user = User.create!
    BrandMembership.create!(user:, brand: @brand)
    token, = Session.issue!(user:, brand: @brand)

    patch "/api/v1/auth/password",
      headers: bearer_headers(token),
      params: { current_password: "secret", password: "new-secret", password_confirmation: "new-secret" }

    assert_response :conflict
    assert_equal({ "error" => "password_credential_required" }, JSON.parse(response.body))
  end

  test "rate limits repeated current-password failures" do
    register_phone
    token = JSON.parse(response.body).fetch("token")
    session = Session.last
    identifier = session.credential.identity_identifier.normalized_value
    5.times do
      AuthAttempt.create!(
        brand: @brand,
        user: session.user,
        credential: session.credential,
        kind: :password,
        result: :failed,
        identifier:,
        ip_address: "127.0.0.1",
        metadata: { purpose: "password_change", failure_stage: "reauthentication" }
      )
    end

    patch "/api/v1/auth/password",
      headers: bearer_headers(token),
      params: { current_password: "secret", password: "new-secret", password_confirmation: "new-secret" }

    assert_response :too_many_requests
    assert_equal({ "error" => "rate_limited" }, JSON.parse(response.body))
    assert response.headers.fetch("Retry-After").to_i.positive?
    assert Identity::PasswordEngine.matches?(credential: session.credential, password: "secret")
  end

  test "login surfaces account_deactivated only after the password has been verified" do
    register_phone
    user = Session.last.user
    Accounts::DeactivateAccount.call(user:, brand: @brand)

    assert_no_difference -> { Session.count } do
      post "/api/v1/auth/password/login",
        params: { identifier: "+27 82 123 4567", password: "secret" }
    end
    assert_response :conflict
    assert_equal({ "error" => "account_deactivated" }, JSON.parse(response.body))

    assert_no_difference -> { Session.count } do
      post "/api/v1/auth/password/login",
        params: { identifier: "+27 82 123 4567", password: "wrong-password" }
    end
    assert_response :unauthorized
    assert_equal({ "error" => "invalid_credentials" }, JSON.parse(response.body))
  end

  test "reactivates a deactivated account and issues a working session" do
    register_phone
    user = Session.last.user
    Accounts::DeactivateAccount.call(user:, brand: @brand)

    assert_difference -> { Session.where(brand: @brand).count }, 1 do
      post "/api/v1/auth/password/reactivation",
        params: { identifier: "+27 82 123 4567", password: "secret" }
    end

    assert_response :created
    body = JSON.parse(response.body)
    assert body.fetch("token").present?
    assert user.brand_memberships.find_by(brand: @brand).active?
    assert SecurityEvent.exists?(event_type: "account.reactivated", user:)

    get "/api/v1/me", headers: bearer_headers(body.fetch("token"))
    assert_response :success
  end

  test "reactivation requires the correct password and leaves the account deactivated on failure" do
    register_phone
    user = Session.last.user
    Accounts::DeactivateAccount.call(user:, brand: @brand)

    assert_no_difference -> { Session.where(brand: @brand).count } do
      post "/api/v1/auth/password/reactivation",
        params: { identifier: "+27 82 123 4567", password: "wrong-password" }
    end

    assert_response :unauthorized
    assert_equal({ "error" => "invalid_credentials" }, JSON.parse(response.body))
    assert user.brand_memberships.find_by(brand: @brand).deactivated?
  end

  test "reactivation fails cleanly for an account that is not deactivated" do
    register_phone

    post "/api/v1/auth/password/reactivation",
      params: { identifier: "+27 82 123 4567", password: "secret" }

    assert_response :conflict
    assert_equal({ "error" => "account_not_deactivated" }, JSON.parse(response.body))
  end

  test "reactivation shares the login throttle budget for the same identifier" do
    register_phone
    user = Session.last.user
    Accounts::DeactivateAccount.call(user:, brand: @brand)
    10.times do
      AuthAttempt.create!(
        brand: @brand, kind: :password, result: :failed,
        identifier: "27821234567", ip_address: "127.0.0.1",
        metadata: { purpose: "password_login" }
      )
    end

    post "/api/v1/auth/password/reactivation",
      params: { identifier: "+27 82 123 4567", password: "secret" }

    assert_response :too_many_requests
    assert_equal({ "error" => "rate_limited" }, JSON.parse(response.body))
    assert user.brand_memberships.find_by(brand: @brand).deactivated?
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
