module Identity
  class PhoneOtpRequester
    Result = Data.define(:success?, :challenge, :error)

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
      return Result.new(false, nil, :brand_required) if brand.blank?

      identifier = PhoneNormalizer.call(phone)
      return Result.new(false, nil, :invalid_phone) if identifier.blank?

      challenge = nil

      OtpChallenge.transaction do
        expire_existing_challenges(identifier)
        challenge = create_challenge(identifier)
        record_security_event(challenge)
      end

      Result.new(true, challenge, nil)
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

      OtpChallenge.create!(
        brand:,
        kind: :phone_otp,
        identifier:,
        code_digest: OtpChallenge.digest_code(code),
        expires_at: EXPIRES_IN.from_now,
        ip_address:,
        user_agent:
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
  end
end
