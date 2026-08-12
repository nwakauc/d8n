module Identity
  class PhoneOtpRequester
    Result = Data.define(:success?, :challenge, :error, :retry_after)

    EXPIRES_IN = 10.minutes

    def self.call(...)
      new(...).call
    end

    def initialize(brand:, phone:, ip_address: nil, user_agent: nil)
      @brand = brand
      @phone = phone
      @ip_address = ip_address
      @user_agent = user_agent
    end

    def call
      return Result.new(false, nil, :brand_required, nil) if brand.blank?

      identifier = PhoneNormalizer.call(phone)
      return Result.new(false, nil, :invalid_phone, nil) if identifier.blank?

      throttle = OtpThrottle.call(brand:, identifier:, ip_address:)
      return throttled_result(identifier, throttle) if throttle.throttled?

      challenge = nil

      OtpChallenge.transaction do
        expire_existing_challenges(identifier)
        challenge, code = create_challenge(identifier)
        send_otp(identifier, code, challenge)
        record_security_event(challenge)
      end

      Result.new(true, challenge, nil, nil)
    end

    private

    attr_reader :brand, :phone, :ip_address, :user_agent

    def expire_existing_challenges(identifier)
      OtpChallenge.active.where(
        brand:,
        identifier:,
        kind: :phone_otp
      ).update_all(consumed_at: Time.current, updated_at: Time.current)
    end

    def create_challenge(identifier)
      code = OtpCode.generate

      challenge = OtpChallenge.create!(
        brand:,
        kind: :phone_otp,
        identifier:,
        code_digest: OtpChallenge.digest_code(code),
        expires_at: EXPIRES_IN.from_now,
        ip_address:,
        user_agent:
      )

      [ challenge, code ]
    end

    def send_otp(identifier, code, challenge)
      Notifications::SmsSender.call(
        brand:,
        recipient: identifier,
        body: "#{brand.name} verification code: #{code}",
        metadata: {
          purpose: "phone_otp",
          challenge_id: challenge.id
        }
      )
    end

    def record_security_event(challenge)
      SecurityEvent.create!(
        brand:,
        event_type: "auth.phone_otp.requested",
        severity: :info,
        ip_address:,
        user_agent:,
        metadata: { challenge_id: challenge.id }
      )
    end

    def throttled_result(identifier, throttle)
      AuthAttempt.create!(
        brand:,
        kind: :phone_otp,
        result: :throttled,
        identifier:,
        ip_address:,
        user_agent:,
        metadata: { throttle_scope: throttle.scope.to_s }
      )
      SecurityEvent.create!(
        brand:,
        event_type: "auth.phone_otp.throttled",
        severity: :warning,
        ip_address:,
        user_agent:,
        metadata: {
          throttle_scope: throttle.scope.to_s,
          retry_after: throttle.retry_after,
          identifier_kind: "phone",
          identifier_last4: identifier.last(4)
        }
      )

      Result.new(false, nil, :rate_limited, throttle.retry_after)
    end
  end
end
