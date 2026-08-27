module Identity
  # Step 2 of signed-out password recovery: consume the delivered recovery code and,
  # on success, mint a single-use, short-lived reset authorization token. The raw
  # token is returned once to the caller and stored only as an HMAC digest (reusing
  # the OtpChallenge hashed-secret convention), so it satisfies ADR 0012's rule that
  # reset secrets are never stored or logged in plaintext.
  #
  # Enumeration resistance: an unknown identifier, a missing challenge, and a
  # wrong code all return the same generic :invalid_code. Expired/used lifecycle
  # is disclosed only when the caller proves possession of the delivered secret.
  class RecoveryVerifier
    Result = Data.define(:success?, :error, :reset_token, :expires_at)
    MAX_ATTEMPTS = 5
    RECOVERY_KIND = "password_recovery"
    RESET_KIND = "password_reset"
    RESET_TOKEN_TTL = 15.minutes
    RESET_TOKEN_BYTES = 32

    def self.call(...)
      new(...).call
    end

    def initialize(brand:, identifier:, code:, ip_address: nil, user_agent: nil)
      @brand = brand
      @identifier_input = identifier
      @code = code.to_s
      @ip_address = ip_address
      @user_agent = user_agent
    end

    def call
      return failure(:invalid_code) unless active_brand?

      login_identifier = LoginIdentifier.call(identifier_input, brand:)
      return failure(:invalid_code) if login_identifier.blank?

      identifiers = IdentityIdentifier.kept.where(
        kind: login_identifier.kind,
        normalized_value: login_identifier.lookup_values
      ).limit(2).to_a
      identity_identifier = identifiers.one? ? identifiers.first : nil
      return failure(:invalid_code) if identity_identifier.blank?

      challenge = latest_recovery_challenge(identity_identifier)
      return failed(identity_identifier) if challenge.blank?

      verify_locked(challenge, identity_identifier)
    end

    private

    attr_reader :brand, :identifier_input, :code, :ip_address, :user_agent

    def verify_locked(challenge, identity_identifier)
      OtpChallenge.transaction do
        challenge.lock!
        next terminal(challenge, identity_identifier) if challenge.consumed? || challenge.expired?
        next locked(challenge, identity_identifier) if challenge.attempt_count >= MAX_ATTEMPTS
        next wrong_code(challenge, identity_identifier) unless challenge.code_matches?(code)

        challenge.consume!
        raw_token, expires_at = issue_reset_authorization(identity_identifier)
        record_event(identity_identifier, "verified")
        success(raw_token, expires_at)
      end
    end

    def issue_reset_authorization(identity_identifier)
      raw_token = SecureRandom.urlsafe_base64(RESET_TOKEN_BYTES)
      expires_at = RESET_TOKEN_TTL.from_now

      # Only one live reset authorization per identifier: supersede any earlier one.
      OtpChallenge.active.where(brand:, identity_identifier:, kind: RESET_KIND)
        .update_all(consumed_at: Time.current, updated_at: Time.current)
      OtpChallenge.create!(
        brand:,
        identity_identifier:,
        kind: RESET_KIND,
        identifier: identity_identifier.normalized_value,
        code_digest: OtpChallenge.digest_code(raw_token),
        expires_at:,
        ip_address:,
        user_agent:,
        metadata: { purpose: "password_recovery" }
      )

      [ raw_token, expires_at ]
    end

    def wrong_code(challenge, identity_identifier)
      challenge.increment!(:attempt_count)
      if challenge.attempt_count >= MAX_ATTEMPTS
        challenge.consume!
        record_event(identity_identifier, "locked", severity: :warning)
      else
        record_event(identity_identifier, "failed", severity: :warning)
      end
      failure(challenge.attempt_count >= MAX_ATTEMPTS ? :verification_attempts_exhausted : :invalid_code)
    end

    def locked(challenge, identity_identifier)
      challenge.consume!
      record_event(identity_identifier, "locked", severity: :warning)
      failure(:verification_attempts_exhausted)
    end

    # Preserve anti-enumeration: lifecycle is disclosed only when the caller
    # presents the exact secret previously delivered to this identifier.
    def terminal(challenge, identity_identifier)
      return failed(identity_identifier) unless challenge.code_matches?(code)

      error = if challenge.expired?
        :verification_code_expired
      elsif challenge.attempt_count >= MAX_ATTEMPTS
        :verification_attempts_exhausted
      else
        :verification_code_used
      end
      record_event(identity_identifier, "failed", severity: :warning)
      failure(error)
    end

    def failed(identity_identifier)
      OtpChallenge.digest_code(code)
      record_event(identity_identifier, "failed", severity: :warning)
      failure(:invalid_code)
    end

    def latest_recovery_challenge(identity_identifier)
      OtpChallenge.where(
        brand:,
        identity_identifier:,
        kind: RECOVERY_KIND
      ).order(created_at: :desc).first
    end

    def record_event(identity_identifier, outcome, severity: :info)
      SecurityEvent.create!(
        brand:,
        user: identity_identifier.user,
        event_type: "auth.password_recovery.#{outcome}",
        severity:,
        ip_address:,
        user_agent:,
        metadata: {
          identifier_kind: identity_identifier.kind,
          identifier_last4: identity_identifier.normalized_value.last(4)
        }
      )
    end

    def active_brand?
      brand.present? && brand.active? && brand.deleted_at.nil?
    end

    def success(reset_token, expires_at)
      Result.new(true, nil, reset_token, expires_at)
    end

    def failure(error)
      Result.new(false, error, nil, nil)
    end
  end
end
