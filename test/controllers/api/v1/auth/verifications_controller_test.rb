require "test_helper"

class Api::V1::Auth::VerificationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @brand = Brand.create!(
      slug: "hookus",
      name: "HookUs",
      auth_methods: %w[ phone_password email_password ]
    )
    BrandDomain.create!(brand: @brand, host: "hookus.test")
    @user = User.create!
    @membership = BrandMembership.create!(brand: @brand, user: @user)
    @phone = @user.identity_identifiers.create!(kind: :phone, normalized_value: "+27 82 123 4567")
    @email = @user.identity_identifiers.create!(kind: :email, normalized_value: "ada@example.com")
    @credential = @user.credentials.create!(identity_identifier: @phone, kind: :password)
    Identity::PasswordEngine.set!(credential: @credential, password: "secret")
    @token, = Session.issue!(brand: @brand, user: @user, credential: @credential)
    host! "hookus.test"
    Notifications::Sms::TestGateway.clear
    ActionMailer::Base.deliveries.clear
    # Delivery is now enqueued after commit (Notifications::DeliverChallengeJob).
    # Run it inline so these verification specs still observe the delivered
    # code/email synchronously; the async contract is covered by the job's tests.
    @previous_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :inline
  end

  teardown do
    ActiveJob::Base.queue_adapter = @previous_queue_adapter
  end

  test "requires an authenticated brand session" do
    assert_no_difference -> { OtpChallenge.count } do
      post "/api/v1/auth/verification", params: { kind: "phone" }
    end

    assert_response :unauthorized
  end

  test "requests a purpose-bound phone verification without creating account state" do
    with_sms_provider("test") do
      assert_no_account_or_session_changes do
        assert_difference -> { OtpChallenge.phone_verification.count }, 1 do
          post "/api/v1/auth/verification",
            headers: bearer_headers,
            params: { kind: "phone" }
        end
      end
    end

    assert_response :accepted
    challenge = OtpChallenge.phone_verification.last
    assert_equal @phone, challenge.identity_identifier
    assert_equal @brand, challenge.brand
    assert_equal "identifier_verification", challenge.metadata.fetch("purpose")
    assert_equal @user, NotificationDelivery.sms.last.user
    assert_equal "identifier_verification", NotificationDelivery.sms.last.metadata.fetch("purpose")
  end

  test "verifies the caller's phone without issuing or changing a session" do
    request_phone_code
    code = delivered_sms_code

    assert_no_account_or_session_changes do
      patch "/api/v1/auth/verification",
        headers: bearer_headers,
        params: { kind: "phone", code: }
    end

    assert_response :success
    assert @phone.reload.verified_at.present?
    assert OtpChallenge.phone_verification.last.consumed?
    assert_equal({ "kind" => "phone", "verified" => true }, JSON.parse(response.body).fetch("identifier"))
    assert SecurityEvent.exists?(event_type: "auth.phone_verification.succeeded", user: @user)
  end

  test "delivers and verifies an email challenge" do
    assert_difference -> { ActionMailer::Base.deliveries.count }, 1 do
      post "/api/v1/auth/verification",
        headers: bearer_headers,
        params: { kind: "email" }
    end
    assert_response :accepted

    mail = ActionMailer::Base.deliveries.last
    assert_equal [ "ada@example.com" ], mail.to
    code = mail.text_part.body.to_s[/\b\d{6}\b/]
    assert code.present?

    assert_no_difference -> { Session.count } do
      patch "/api/v1/auth/verification",
        headers: bearer_headers,
        params: { kind: "email", code: }
    end

    assert_response :success
    assert @email.reload.verified_at.present?
    assert_equal "email", JSON.parse(response.body).dig("identifier", "kind")
  end

  test "fails closed when production email delivery is not configured" do
    previous = ENV["D8N_EMAIL_PROVIDER"]
    ENV["D8N_EMAIL_PROVIDER"] = "required"

    post "/api/v1/auth/verification",
      headers: bearer_headers,
      params: { kind: "email" }

    assert_response :service_unavailable
    assert_equal({ "error" => "delivery_unavailable" }, JSON.parse(response.body))
    assert OtpChallenge.email_verification.last.consumed?
    assert_nil @email.reload.verified_at
  ensure
    ENV["D8N_EMAIL_PROVIDER"] = previous
  end

  test "returns a generic accepted response when the caller has no requested identifier" do
    @email.destroy!

    assert_no_difference -> { OtpChallenge.count } do
      post "/api/v1/auth/verification",
        headers: bearer_headers,
        params: { kind: "email" }
    end

    assert_response :accepted
    assert_equal({ "message" => "If this identifier can receive D8N codes, a code has been sent." }, JSON.parse(response.body))
  end

  test "rejects unsupported identifier kinds" do
    post "/api/v1/auth/verification",
      headers: bearer_headers,
      params: { kind: "oauth_provider_uid" }

    assert_response :unprocessable_entity
    assert_equal({ "error" => "invalid_kind" }, JSON.parse(response.body))
  end

  test "does not accept another user's challenge" do
    other_user = User.create!
    other_identifier = other_user.identity_identifiers.create!(kind: :phone, normalized_value: "+27 82 999 9999")
    challenge = create_challenge(identity_identifier: other_identifier, kind: :phone_verification)

    patch "/api/v1/auth/verification",
      headers: bearer_headers,
      params: { kind: "phone", code: "123456" }

    assert_response :unauthorized
    assert_nil @phone.reload.verified_at
    assert_nil other_identifier.reload.verified_at
    assert_not challenge.reload.consumed?
  end

  test "does not accept a challenge issued through another brand" do
    other_brand = Brand.create!(slug: "date9ja", name: "Date9ja")
    challenge = create_challenge(identity_identifier: @phone, kind: :phone_verification, brand: other_brand)

    patch "/api/v1/auth/verification",
      headers: bearer_headers,
      params: { kind: "phone", code: "123456" }

    assert_response :unauthorized
    assert_nil @phone.reload.verified_at
    assert_not challenge.reload.consumed?
  end

  test "does not use a phone-purpose code for email verification" do
    create_challenge(identity_identifier: @phone, kind: :phone_verification)

    patch "/api/v1/auth/verification",
      headers: bearer_headers,
      params: { kind: "email", code: "123456" }

    assert_response :unauthorized
    assert_nil @email.reload.verified_at
  end

  test "rejects expired and consumed codes" do
    expired = create_challenge(
      identity_identifier: @phone,
      kind: :phone_verification,
      expires_at: 1.minute.ago
    )

    patch "/api/v1/auth/verification",
      headers: bearer_headers,
      params: { kind: "phone", code: "123456" }

    assert_response :unauthorized
    assert_nil @phone.reload.verified_at
    expired.update!(consumed_at: Time.current)
  end

  test "locks a challenge after five wrong attempts and prevents replay" do
    request_phone_code
    challenge = OtpChallenge.phone_verification.last

    5.times do
      patch "/api/v1/auth/verification",
        headers: bearer_headers,
        params: { kind: "phone", code: "000000" }
      assert_response :unauthorized
    end

    assert challenge.reload.consumed?
    assert_equal 5, challenge.attempt_count
    assert_nil @phone.reload.verified_at

    patch "/api/v1/auth/verification",
      headers: bearer_headers,
      params: { kind: "phone", code: delivered_sms_code }
    assert_response :unauthorized
  end

  test "rate limits immediate resend with Retry-After" do
    request_phone_code

    assert_no_difference -> { OtpChallenge.count } do
      with_sms_provider("test") do
        post "/api/v1/auth/verification",
          headers: bearer_headers,
          params: { kind: "phone" }
      end
    end

    assert_response :too_many_requests
    assert response.headers.fetch("Retry-After").to_i.positive?
  end

  test "legacy unauthenticated phone OTP login routes are removed" do
    post "/api/v1/auth/phone/request_otp", params: { phone: "+27 82 123 4567" }
    assert_response :not_found

    post "/api/v1/auth/phone/verify_otp", params: { phone: "+27 82 123 4567", code: "123456" }
    assert_response :not_found
  end

  private

  def request_phone_code
    with_sms_provider("test") do
      post "/api/v1/auth/verification",
        headers: bearer_headers,
        params: { kind: "phone" }
    end
    assert_response :accepted
  end

  def delivered_sms_code
    Notifications::Sms::TestGateway.deliveries.last.fetch(:body)[/\b\d{6}\b/]
  end

  def create_challenge(identity_identifier:, kind:, brand: @brand, expires_at: 10.minutes.from_now)
    OtpChallenge.create!(
      brand:,
      identity_identifier:,
      kind:,
      identifier: identity_identifier.normalized_value,
      code_digest: OtpChallenge.digest_code("123456"),
      expires_at:,
      metadata: { purpose: "identifier_verification" }
    )
  end

  def assert_no_account_or_session_changes(&)
    assert_no_difference -> { User.count } do
      assert_no_difference -> { IdentityIdentifier.count } do
        assert_no_difference -> { Credential.count } do
          assert_no_difference -> { BrandMembership.count } do
            assert_no_difference -> { Session.count }, &
          end
        end
      end
    end
  end

  def bearer_headers
    { "Authorization" => "Bearer #{@token}" }
  end

  def with_sms_provider(provider)
    previous = ENV["D8N_SMS_PROVIDER"]
    ENV["D8N_SMS_PROVIDER"] = provider
    yield
  ensure
    ENV["D8N_SMS_PROVIDER"] = previous
  end
end
