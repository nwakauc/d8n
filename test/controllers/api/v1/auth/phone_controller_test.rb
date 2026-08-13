require "test_helper"

class Api::V1::Auth::PhoneControllerTest < ActionDispatch::IntegrationTest
  setup do
    @brand = Brand.create!(slug: "hookus", name: "HookUs")
    BrandDomain.create!(brand: @brand, host: "hookus.test")
    host! "hookus.test"
    Notifications::Sms::TestGateway.clear
  end

  test "requests a phone OTP without exposing the generated code" do
    with_sms_provider("test") do
    with_otp_code("123456") do
      assert_difference -> { OtpChallenge.count }, 1 do
        assert_difference -> { NotificationDelivery.sms.sent.count }, 1 do
          assert_difference -> { SecurityEvent.where(event_type: "auth.phone_otp.requested").count }, 1 do
            post "/api/v1/auth/phone/request_otp", params: { phone: "+27 82 123 4567" }
          end
        end
      end
    end
    end

    assert_response :accepted
    response_body = JSON.parse(response.body)
    assert_equal "If the phone number can receive D8N codes, a code has been sent.", response_body.fetch("message")
    assert_not_includes response.body, "123456"

    challenge = OtpChallenge.last
    assert_equal @brand, challenge.brand
    assert_equal "27821234567", challenge.identifier
    assert challenge.phone_otp?
    assert challenge.code_matches?("123456")

    delivery = NotificationDelivery.last
    assert_equal @brand, delivery.brand
    assert_equal "test", delivery.provider
    assert_equal "27821234567", delivery.recipient
    assert_equal({ "purpose" => "phone_otp", "challenge_id" => challenge.id }, delivery.metadata)

    sms = Notifications::Sms::TestGateway.deliveries.last
    assert_equal "27821234567", sms.fetch(:to)
    assert_includes sms.fetch(:body), "123456"
  end

  test "verify OTP creates identity, brand membership, credential, and session" do
    request_phone_otp

    assert_difference -> { User.count }, 1 do
      assert_difference -> { IdentityIdentifier.count }, 1 do
        assert_difference -> { Credential.count }, 1 do
          assert_difference -> { BrandMembership.count }, 1 do
            assert_difference -> { Session.count }, 1 do
              post "/api/v1/auth/phone/verify_otp",
                params: { phone: "+27 82 123 4567", code: "123456", device_name: "iPhone" }
            end
          end
        end
      end
    end

    assert_response :created
    response_body = JSON.parse(response.body)
    token = response_body.fetch("token")
    user = User.last
    session = Session.last

    assert token.present?
    assert_equal "Bearer", response_body.fetch("token_type")
    assert_equal user.id, response_body.fetch("user_id")
    assert_equal "hookus", response_body.fetch("brand").fetch("slug")
    assert_equal Session.digest_token(token), session.token_digest
    assert_not_equal token, session.token_digest
    assert_equal "iPhone", session.device_name
    assert_equal @brand, session.brand
    assert_equal user.credentials.last, session.credential
    assert_equal @brand, user.brand_memberships.last.brand
    assert_equal "27821234567", user.identity_identifiers.last.normalized_value
    assert user.credentials.last.phone_otp?
    assert OtpChallenge.last.consumed?
  end

  test "verify OTP reuses an existing D8N identity without creating a second account" do
    request_phone_otp
    post "/api/v1/auth/phone/verify_otp", params: { phone: "+27 82 123 4567", code: "123456" }
    user = User.last

    OtpChallenge.update_all(created_at: 11.minutes.ago, updated_at: 11.minutes.ago)
    request_phone_otp

    assert_no_difference -> { User.count } do
      assert_no_difference -> { IdentityIdentifier.count } do
        post "/api/v1/auth/phone/verify_otp", params: { phone: "+27 82 123 4567", code: "123456" }
      end
    end

    assert_response :created
    assert_equal user, Session.last.user
  end

  test "verify OTP rejects wrong codes and records a failed attempt" do
    request_phone_otp

    assert_no_difference -> { User.count } do
      assert_no_difference -> { Session.count } do
        assert_difference -> { AuthAttempt.failed.count }, 1 do
          post "/api/v1/auth/phone/verify_otp", params: { phone: "+27 82 123 4567", code: "999999" }
        end
      end
    end

    assert_response :unauthorized
    assert_equal({ "error" => "invalid_code" }, JSON.parse(response.body))
    assert_equal 1, OtpChallenge.last.attempt_count
  end

  test "verify OTP cannot reuse a consumed challenge" do
    request_phone_otp
    post "/api/v1/auth/phone/verify_otp", params: { phone: "+27 82 123 4567", code: "123456" }
    assert_response :created

    assert_no_difference -> { Session.count } do
      post "/api/v1/auth/phone/verify_otp", params: { phone: "+27 82 123 4567", code: "123456" }
    end

    assert_response :unauthorized
  end

  test "verify OTP does not authenticate a suspended user" do
    account = create_phone_account(user_status: :suspended)
    request_phone_otp

    assert_no_difference -> { Session.count } do
      post "/api/v1/auth/phone/verify_otp", params: { phone: "+27 82 123 4567", code: "123456" }
    end

    assert_response :unauthorized
    assert OtpChallenge.last.consumed?
    assert_denied_event("user_inactive", account.fetch(:user))
  end

  test "verify OTP does not authenticate a revoked credential" do
    account = create_phone_account(credential_status: :revoked)
    request_phone_otp

    assert_no_difference -> { Session.count } do
      post "/api/v1/auth/phone/verify_otp", params: { phone: "+27 82 123 4567", code: "123456" }
    end

    assert_response :unauthorized
    assert_denied_event("credential_inactive", account.fetch(:user))
  end

  test "verify OTP does not reactivate an inactive brand membership" do
    account = create_phone_account(membership_status: :left)
    request_phone_otp

    assert_no_difference -> { Session.count } do
      post "/api/v1/auth/phone/verify_otp", params: { phone: "+27 82 123 4567", code: "123456" }
    end

    assert_response :unauthorized
    assert account.fetch(:membership).reload.left?
    assert_denied_event("membership_inactive", account.fetch(:user))
  end

  test "request OTP requires brand context" do
    host! "unknown.test"

    post "/api/v1/auth/phone/request_otp", params: { phone: "+27 82 123 4567" }

    assert_response :not_found
    assert_equal({ "error" => "brand_required" }, JSON.parse(response.body))
  end

  test "request OTP is rate limited by phone cooldown" do
    request_phone_otp

    assert_no_difference -> { OtpChallenge.count } do
      assert_difference -> { AuthAttempt.throttled.count }, 1 do
        post "/api/v1/auth/phone/request_otp", params: { phone: "+27 82 123 4567" }
      end
    end

    assert_response :too_many_requests
    assert_equal({ "error" => "rate_limited" }, JSON.parse(response.body))
    assert response.headers["Retry-After"].present?
  end

  test "request OTP is rate limited by rolling phone window" do
    5.times do |index|
      create_challenge(
        identifier: "27821234567",
        created_at: (9 - index).minutes.ago
      )
    end

    assert_no_difference -> { OtpChallenge.count } do
      assert_difference -> { AuthAttempt.throttled.count }, 1 do
        post "/api/v1/auth/phone/request_otp", params: { phone: "+27 82 123 4567" }
      end
    end

    assert_response :too_many_requests
  end

  test "request OTP is rate limited by rolling IP window" do
    20.times do |index|
      create_challenge(
        identifier: "27821234#{index.to_s.rjust(3, '0')}",
        created_at: (9.minutes.ago + index.seconds)
      )
    end

    assert_no_difference -> { OtpChallenge.count } do
      assert_difference -> { AuthAttempt.throttled.count }, 1 do
        post "/api/v1/auth/phone/request_otp", params: { phone: "+27 82 999 9999" }
      end
    end

    assert_response :too_many_requests
  end

  private

  def request_phone_otp
    with_otp_code("123456") do
      post "/api/v1/auth/phone/request_otp", params: { phone: "+27 82 123 4567" }
    end
    assert_response :accepted
  end

  def create_phone_account(user_status: :active, credential_status: :active, membership_status: :active)
    user = User.create!(status: user_status)
    identifier = IdentityIdentifier.create!(
      user:,
      kind: :phone,
      normalized_value: "+27 82 123 4567",
      verified_at: Time.current
    )
    credential = Credential.create!(
      user:,
      identity_identifier: identifier,
      kind: :phone_otp,
      status: credential_status,
      verified_at: Time.current
    )
    membership = BrandMembership.create!(user:, brand: @brand, status: membership_status)

    { user:, identifier:, credential:, membership: }
  end

  def assert_denied_event(reason, user)
    event = SecurityEvent.find_by!(event_type: "auth.phone_otp.denied")
    assert_equal user, event.user
    assert_equal reason, event.metadata.fetch("reason")
  end

  def create_challenge(identifier:, created_at:)
    challenge = OtpChallenge.create!(
      brand: @brand,
      kind: :phone_otp,
      identifier:,
      code_digest: OtpChallenge.digest_code("123456"),
      expires_at: 10.minutes.from_now,
      ip_address: "127.0.0.1"
    )
    challenge.update_columns(created_at:, updated_at: created_at)
    challenge
  end

  def with_otp_code(code)
    singleton_class = class << Identity::OtpCode; self; end
    original_method = Identity::OtpCode.method(:generate)
    singleton_class.define_method(:generate) { code }

    yield
  ensure
    singleton_class.define_method(:generate) { original_method.call }
  end

  def with_sms_provider(provider)
    previous_provider = ENV["D8N_SMS_PROVIDER"]
    ENV["D8N_SMS_PROVIDER"] = provider

    yield
  ensure
    ENV["D8N_SMS_PROVIDER"] = previous_provider
  end
end
