module Identity
  class VerificationVerifier
    Result = Data.define(:success?, :error, :identity_identifier)
    MAX_ATTEMPTS = 5
    SUPPORTED_KINDS = VerificationRequester::SUPPORTED_KINDS

    def self.call(...)
      new(...).call
    end

    def initialize(user:, brand:, kind:, code:, ip_address: nil, user_agent: nil)
      @user = user
      @brand = brand
      @kind = kind.to_s
      @code = code.to_s
      @ip_address = ip_address
      @user_agent = user_agent
    end

    def call
      return failure(:verification_code_invalid) unless SUPPORTED_KINDS.include?(kind)

      identity_identifier = owned_identifier
      return failure(:verification_code_invalid) if identity_identifier.blank?

      challenge = latest_challenge(identity_identifier)
      return failed_without_challenge(identity_identifier) if challenge.blank?

      verify_locked(challenge, identity_identifier)
    end

    private

    attr_reader :user, :brand, :kind, :code, :ip_address, :user_agent

    def verify_locked(challenge, identity_identifier)
      OtpChallenge.transaction do
        challenge.lock!
        next expired(challenge, identity_identifier) if challenge.expired?
        next terminal(challenge, identity_identifier) if challenge.consumed?
        next exhausted(challenge, identity_identifier) if challenge.attempt_count >= MAX_ATTEMPTS
        next wrong_code(challenge, identity_identifier) unless challenge.code_matches?(code)

        challenge.consume!
        identity_identifier.update!(verified_at: Time.current, last_seen_at: Time.current)
        record_attempt(identity_identifier, result: :succeeded)
        success(identity_identifier)
      end
    end

    def wrong_code(challenge, identity_identifier)
      challenge.increment!(:attempt_count)
      result = challenge.attempt_count >= MAX_ATTEMPTS ? :locked : :failed
      challenge.consume! if result == :locked
      record_attempt(identity_identifier, result:)
      failure(result == :locked ? :verification_attempts_exhausted : :verification_code_invalid)
    end

    def expired(_challenge, identity_identifier)
      record_attempt(identity_identifier, result: :failed)
      failure(:verification_code_expired)
    end

    def terminal(challenge, identity_identifier)
      error = challenge.attempt_count >= MAX_ATTEMPTS ? :verification_attempts_exhausted : :verification_code_used
      record_attempt(identity_identifier, result: error == :verification_attempts_exhausted ? :locked : :failed)
      failure(error)
    end

    def exhausted(challenge, identity_identifier)
      challenge.consume! unless challenge.consumed?
      record_attempt(identity_identifier, result: :locked)
      failure(:verification_attempts_exhausted)
    end

    def failed_without_challenge(identity_identifier)
      OtpChallenge.digest_code(code)
      record_attempt(identity_identifier, result: :failed)
      failure(:verification_code_invalid)
    end

    def owned_identifier
      user.identity_identifiers.kept.find_by(kind:)
    end

    def latest_challenge(identity_identifier)
      OtpChallenge.where(
        brand:,
        identity_identifier:,
        kind: "#{kind}_verification"
      ).order(created_at: :desc).first
    end

    def attempt_kind
      kind == "phone" ? :phone_otp : :email_otp
    end

    def record_attempt(identity_identifier, result:)
      AuthAttempt.create!(
        brand:,
        user:,
        identity_identifier:,
        kind: attempt_kind,
        result:,
        identifier: identity_identifier.normalized_value,
        ip_address:,
        user_agent:,
        metadata: { purpose: "identifier_verification" }
      )
      SecurityEvent.create!(
        brand:,
        user:,
        event_type: "auth.#{kind}_verification.#{result}",
        severity: result == :succeeded ? :info : :warning,
        ip_address:,
        user_agent:,
        metadata: {
          identifier_kind: kind,
          identifier_last4: identity_identifier.normalized_value.last(4)
        }
      )
    end

    def success(identity_identifier)
      Result.new(true, nil, identity_identifier)
    end

    def failure(error)
      Result.new(false, error, nil)
    end
  end
end
