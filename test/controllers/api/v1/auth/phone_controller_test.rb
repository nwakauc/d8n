require "test_helper"

class Api::V1::Auth::PhoneControllerTest < ActionDispatch::IntegrationTest
  setup do
    @brand = Brand.create!(slug: "hookus", name: "HookUs")
    BrandDomain.create!(brand: @brand, host: "hookus.test")
    host! "hookus.test"
  end

  test "requests a phone OTP without exposing the generated code" do
    with_otp_code("123456") do
      assert_difference -> { OtpChallenge.count }, 1 do
        assert_difference -> { SecurityEvent.where(event_type: "auth.phone_otp.requested").count }, 1 do
          post "/api/v1/auth/phone/request_otp", params: { phone: "+27 82 123 4567" }
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
    assert_equal @brand, user.brand_memberships.last.brand
    assert_equal "27821234567", user.identity_identifiers.last.normalized_value
    assert user.credentials.last.phone_otp?
    assert OtpChallenge.last.consumed?
  end

  test "verify OTP reuses an existing D8N identity without creating a second account" do
    request_phone_otp
    post "/api/v1/auth/phone/verify_otp", params: { phone: "+27 82 123 4567", code: "123456" }
    user = User.last

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

  test "request OTP requires brand context" do
    host! "unknown.test"

    post "/api/v1/auth/phone/request_otp", params: { phone: "+27 82 123 4567" }

    assert_response :not_found
    assert_equal({ "error" => "brand_required" }, JSON.parse(response.body))
  end

  private

  def request_phone_otp
    with_otp_code("123456") do
      post "/api/v1/auth/phone/request_otp", params: { phone: "+27 82 123 4567" }
    end
    assert_response :accepted
  end

  def with_otp_code(code)
    singleton_class = class << Identity::OtpCode; self; end
    original_method = Identity::OtpCode.method(:generate)
    singleton_class.define_method(:generate) { code }

    yield
  ensure
    singleton_class.define_method(:generate) { original_method.call }
  end
end
