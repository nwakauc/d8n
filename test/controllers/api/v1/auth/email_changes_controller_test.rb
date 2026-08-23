require "test_helper"

class Api::V1::Auth::EmailChangesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @brand = Brand.create!(
      slug: "dateza",
      name: "DateZA",
      auth_methods: %w[ phone_password email_password ]
    )
    BrandDomain.create!(brand: @brand, host: "dateza.test")
    @user = User.create!
    BrandMembership.create!(brand: @brand, user: @user)
    @identifier = @user.identity_identifiers.create!(
      kind: :email,
      normalized_value: "wrong@example.com"
    )
    @credential = @user.credentials.create!(identity_identifier: @identifier, kind: :password)
    Identity::PasswordEngine.set!(credential: @credential, password: "secret")
    @token, @session = Session.issue!(brand: @brand, user: @user, credential: @credential)
    host! "dateza.test"
    ActionMailer::Base.deliveries.clear
    @previous_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :inline
  end

  teardown do
    ActiveJob::Base.queue_adapter = @previous_queue_adapter
  end

  test "requires an authenticated session" do
    assert_no_difference -> { OtpChallenge.email_change.count } do
      post "/api/v1/auth/email/change",
        params: { email: "correct@example.com", current_password: "secret" }
    end

    assert_response :unauthorized
  end

  test "sends a purpose-bound branded code to the proposed email without changing login early" do
    assert_difference -> { OtpChallenge.email_change.count }, 1 do
      assert_difference -> { ActionMailer::Base.deliveries.count }, 1 do
        request_change(email: " CORRECT@Example.COM ")
      end
    end

    assert_response :accepted
    assert_equal "wrong@example.com", @identifier.reload.normalized_value
    assert_nil @identifier.verified_at

    challenge = OtpChallenge.email_change.last
    assert_equal @brand, challenge.brand
    assert_equal @identifier, challenge.identity_identifier
    assert_equal "correct@example.com", challenge.identifier
    assert_equal "email_change", challenge.metadata.fetch("purpose")
    assert_equal @session.id, challenge.metadata.fetch("session_id")
    assert_in_delta 10.minutes.from_now.to_i, challenge.expires_at.to_i, 5

    mail = ActionMailer::Base.deliveries.last
    assert_equal [ "correct@example.com" ], mail.to
    assert_equal "Confirm your new DateZA email", mail.subject
    assert_includes mail.text_part.body.decoded, "confirm your new DateZA email address"
    assert_includes mail.html_part.body.to_s, "DateZA heart logo"
    assert_not_includes mail.to, "wrong@example.com"
  end

  test "verifies the proposed email atomically and revokes other credential sessions" do
    request_change
    code = delivered_code
    _, other_session = Session.issue!(brand: @brand, user: @user, credential: @credential)
    stale_verification = OtpChallenge.create!(
      brand: @brand,
      identity_identifier: @identifier,
      kind: :email_verification,
      identifier: @identifier.normalized_value,
      code_digest: OtpChallenge.digest_code("654321"),
      expires_at: 10.minutes.from_now
    )

    assert_no_difference [ -> { IdentityIdentifier.count }, -> { Credential.count } ] do
      patch "/api/v1/auth/email/change",
        headers: bearer_headers(@token),
        params: { email: "correct@example.com", code: }
    end

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal({ "kind" => "email", "verified" => true }, body.fetch("identifier"))
    assert_equal 1, body.fetch("revoked_session_count")
    assert_equal "correct@example.com", @identifier.reload.normalized_value
    assert @identifier.verified_at.present?
    assert_equal @identifier, @credential.reload.identity_identifier
    assert Identity::PasswordEngine.matches?(credential: @credential, password: "secret")
    assert_not @session.reload.revoked?
    assert other_session.reload.revoked?
    assert stale_verification.reload.consumed?
    assert OtpChallenge.email_change.last.consumed?

    event = SecurityEvent.find_by!(event_type: "auth.email_change.succeeded", user: @user)
    assert_equal ".com", event.metadata.fetch("old_identifier_last4")
    assert_equal ".com", event.metadata.fetch("new_identifier_last4")
    assert_not_includes event.metadata.to_json, "wrong@example.com"
    assert_not_includes event.metadata.to_json, "correct@example.com"
  end

  test "the old login stops and the verified replacement login works" do
    request_change
    patch "/api/v1/auth/email/change",
      headers: bearer_headers(@token),
      params: { email: "correct@example.com", code: delivered_code }
    assert_response :success

    post "/api/v1/auth/password/login", params: { identifier: "wrong@example.com", password: "secret" }
    assert_response :unauthorized

    post "/api/v1/auth/password/login", params: { identifier: "correct@example.com", password: "secret" }
    assert_response :created
    assert_equal true, JSON.parse(response.body).dig("identifier", "verified")
  end

  test "requires the current password without revealing replacement availability" do
    other_user = User.create!
    other_user.identity_identifiers.create!(kind: :email, normalized_value: "taken@example.com")

    assert_no_difference -> { OtpChallenge.email_change.count } do
      post "/api/v1/auth/email/change",
        headers: bearer_headers(@token),
        params: { email: "taken@example.com", current_password: "wrong-password" }
    end

    assert_response :unauthorized
    assert_equal({ "error" => "invalid_current_password" }, JSON.parse(response.body))
    event = SecurityEvent.find_by!(event_type: "auth.email_change.failed", user: @user)
    assert_equal "reauthentication", event.metadata.fetch("failure_stage")
    assert_not_includes event.to_json, "wrong-password"
  end

  test "returns one generic error for malformed current and occupied replacement emails" do
    other_user = User.create!
    other_user.identity_identifiers.create!(kind: :email, normalized_value: "taken@example.com")

    request_change(email: "wrong@example.com")
    current_response = response.body
    request_change(email: "taken@example.com")
    occupied_response = response.body
    request_change(email: "not-an-email")

    assert_response :unprocessable_entity
    assert_equal current_response, occupied_response
    assert_equal occupied_response, response.body
    assert_equal({ "error" => "email_change_unavailable" }, JSON.parse(response.body))
    assert_empty ActionMailer::Base.deliveries
  end

  test "a challenge is bound to the session that requested it" do
    request_change
    code = delivered_code
    other_token, = Session.issue!(brand: @brand, user: @user, credential: @credential)

    patch "/api/v1/auth/email/change",
      headers: bearer_headers(other_token),
      params: { email: "correct@example.com", code: }

    assert_response :unauthorized
    assert_equal "wrong@example.com", @identifier.reload.normalized_value
    assert_not OtpChallenge.email_change.last.consumed?
  end

  test "does not accept an email-change code issued under another brand" do
    other_brand = Brand.create!(slug: "other", name: "Other")
    challenge = OtpChallenge.create!(
      brand: other_brand,
      identity_identifier: @identifier,
      kind: :email_change,
      identifier: "correct@example.com",
      code_digest: OtpChallenge.digest_code("123456"),
      expires_at: 10.minutes.from_now,
      metadata: { purpose: "email_change", session_id: @session.id }
    )

    patch "/api/v1/auth/email/change",
      headers: bearer_headers(@token),
      params: { email: "correct@example.com", code: "123456" }

    assert_response :unauthorized
    assert_equal "wrong@example.com", @identifier.reload.normalized_value
    assert_not challenge.reload.consumed?
  end

  test "rate limits immediate replacement requests across proposed addresses" do
    request_change
    assert_response :accepted

    assert_no_difference -> { OtpChallenge.email_change.count } do
      request_change(email: "another@example.com")
    end

    assert_response :too_many_requests
    assert response.headers.fetch("Retry-After").to_i.positive?
    assert_equal "wrong@example.com", @identifier.reload.normalized_value
    assert_equal [ "correct@example.com" ], ActionMailer::Base.deliveries.flat_map(&:to)
  end

  test "wrong codes lock after five attempts and cannot be replayed" do
    request_change
    challenge = OtpChallenge.email_change.last

    5.times do
      patch "/api/v1/auth/email/change",
        headers: bearer_headers(@token),
        params: { email: "correct@example.com", code: "000000" }
      assert_response :unauthorized
    end

    assert challenge.reload.consumed?
    assert_equal 5, challenge.attempt_count
    assert_equal "wrong@example.com", @identifier.reload.normalized_value

    patch "/api/v1/auth/email/change",
      headers: bearer_headers(@token),
      params: { email: "correct@example.com", code: delivered_code }
    assert_response :unauthorized
  end

  test "a target claimed after request fails safely and preserves the old email" do
    request_change
    code = delivered_code
    claimant = User.create!
    claimant.identity_identifiers.create!(kind: :email, normalized_value: "correct@example.com")

    patch "/api/v1/auth/email/change",
      headers: bearer_headers(@token),
      params: { email: "correct@example.com", code: }

    assert_response :unprocessable_entity
    assert_equal({ "error" => "email_change_unavailable" }, JSON.parse(response.body))
    assert_equal "wrong@example.com", @identifier.reload.normalized_value
    assert OtpChallenge.email_change.last.consumed?
  end

  test "requires an email-backed password credential" do
    phone = @user.identity_identifiers.create!(kind: :phone, normalized_value: "+27 82 123 4567")
    phone_credential = @user.credentials.create!(identity_identifier: phone, kind: :password)
    Identity::PasswordEngine.set!(credential: phone_credential, password: "secret")
    phone_token, = Session.issue!(brand: @brand, user: @user, credential: phone_credential)

    post "/api/v1/auth/email/change",
      headers: bearer_headers(phone_token),
      params: { email: "correct@example.com", current_password: "secret" }

    assert_response :conflict
    assert_equal({ "error" => "password_credential_required" }, JSON.parse(response.body))
  end

  private

  def request_change(email: "correct@example.com")
    post "/api/v1/auth/email/change",
      headers: bearer_headers(@token),
      params: { email:, current_password: "secret" }
  end

  def delivered_code
    ActionMailer::Base.deliveries.last.text_part.body.decoded[/\b\d{6}\b/]
  end

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end
end
