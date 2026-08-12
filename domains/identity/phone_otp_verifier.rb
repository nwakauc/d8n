module Identity
  class PhoneOtpVerifier
    Result = Data.define(:success?, :error, :user, :session, :raw_token)

    MAX_ATTEMPTS = 5

    def self.call(...)
      new(...).call
    end

    def initialize(brand:, phone:, code:, ip_address: nil, user_agent: nil, device_name: nil)
      @brand = brand
      @phone = phone
      @code = code
      @ip_address = ip_address
      @user_agent = user_agent
      @device_name = device_name
    end

    def call
      return failure(:brand_required) if brand.blank?

      identifier = PhoneNormalizer.call(phone)
      return failure(:invalid_phone, identifier:) if identifier.blank?

      challenge = latest_challenge(identifier)
      return failure(:invalid_code, identifier:) if challenge.blank?
      return lock_challenge(challenge, identifier) if challenge.attempt_count >= MAX_ATTEMPTS
      return failed_code(challenge, identifier) unless challenge.code_matches?(code)

      verify_challenge(challenge, identifier)
    end

    private

    attr_reader :brand, :phone, :code, :ip_address, :user_agent, :device_name

    def latest_challenge(identifier)
      OtpChallenge.active
        .where(brand:, identifier:, kind: :phone_otp)
        .order(created_at: :desc)
        .first
    end

    def failed_code(challenge, identifier)
      challenge.increment!(:attempt_count)
      result = challenge.attempt_count >= MAX_ATTEMPTS ? :locked : :failed

      record_auth_attempt(identifier:, result:)
      record_security_event(identifier:, event_type: "auth.phone_otp.#{result}", severity: :warning)

      Result.new(false, :invalid_code, nil, nil, nil)
    end

    def lock_challenge(challenge, identifier)
      challenge.consume!
      record_auth_attempt(identifier:, result: :locked)
      record_security_event(identifier:, event_type: "auth.phone_otp.locked", severity: :warning)

      Result.new(false, :invalid_code, nil, nil, nil)
    end

    def verify_challenge(challenge, identifier)
      user = nil
      session = nil
      raw_token = nil

      ActiveRecord::Base.transaction do
        challenge.consume!
        user, identity_identifier = user_and_identifier(identifier)
        credential = credential_for(user, identity_identifier)
        brand_membership_for(user)
        raw_token, session = Session.issue!(user:, brand:, device_name:, ip_address:, user_agent:)
        record_auth_attempt(identifier:, result: :succeeded, user:, identity_identifier:, credential:)
        record_security_event(
          identifier:,
          event_type: "auth.phone_otp.succeeded",
          severity: :info,
          user:
        )
      end

      Result.new(true, nil, user, session, raw_token)
    end

    def user_and_identifier(identifier)
      identity_identifier = IdentityIdentifier.kept.find_by(kind: :phone, normalized_value: identifier)
      return [ identity_identifier.user, identity_identifier ] if identity_identifier.present?

      user = User.create!
      identity_identifier = user.identity_identifiers.create!(
        kind: :phone,
        normalized_value: identifier,
        verified_at: Time.current,
        last_seen_at: Time.current
      )

      [ user, identity_identifier ]
    end

    def credential_for(user, identity_identifier)
      Credential.kept.find_or_create_by!(
        user:,
        identity_identifier:,
        kind: :phone_otp
      ) do |credential|
        credential.status = :active
        credential.verified_at = Time.current
      end.tap do |credential|
        credential.update!(last_used_at: Time.current)
      end
    end

    def brand_membership_for(user)
      BrandMembership.kept.find_or_create_by!(user:, brand:) do |membership|
        membership.status = :active
      end
    end

    def failure(error, identifier: nil)
      record_auth_attempt(identifier:, result: :failed) if identifier.present?
      Result.new(false, error, nil, nil, nil)
    end

    def record_auth_attempt(identifier:, result:, user: nil, identity_identifier: nil, credential: nil)
      AuthAttempt.create!(
        brand:,
        user:,
        identity_identifier:,
        credential:,
        kind: :phone_otp,
        result:,
        identifier:,
        ip_address:,
        user_agent:
      )
    end

    def record_security_event(identifier:, event_type:, severity:, user: nil)
      SecurityEvent.create!(
        brand:,
        user:,
        event_type:,
        severity:,
        ip_address:,
        user_agent:,
        metadata: { identifier_kind: "phone", identifier_last4: identifier.to_s.last(4) }
      )
    end
  end
end
