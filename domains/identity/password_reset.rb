module Identity
  # Step 3 of signed-out password recovery: exchange a single-use reset
  # authorization token for a password change. On success the reset token is
  # consumed (replay is rejected), any sibling recovery/reset challenges for the
  # identifier are expired, and EVERY active session issued from the affected
  # password credential is revoked.
  #
  # Session-revocation scope is deliberately D8N-wide (across all brands), matching
  # authenticated PasswordChange. A password credential is a platform-level identity
  # secret shared by every brand-scoped session it backs, so proving control of the
  # new secret must invalidate all of those sessions, not just one brand's. This
  # does not touch BrandMembership: a suspended or `left`/closed membership stays in
  # its current state, and login re-checks lifecycle before issuing a new session.
  class PasswordReset
    Result = Data.define(:success?, :error, :revoked_session_count)
    RESET_KIND = "password_reset"
    RECOVERY_KIND = "password_recovery"
    PURPOSE = "password_recovery"

    def self.call(...)
      new(...).call
    end

    def initialize(brand:, reset_token:, password:, password_confirmation:, ip_address: nil, user_agent: nil)
      @brand = brand
      @reset_token = reset_token.to_s
      @password = password
      @password_confirmation = password_confirmation
      @ip_address = ip_address
      @user_agent = user_agent
    end

    def call
      return failure(:invalid_token) if reset_token.blank? || brand.blank?

      result = nil
      OtpChallenge.transaction do
        challenge = OtpChallenge.where(
          brand:,
          kind: RESET_KIND,
          code_digest: OtpChallenge.digest_code(reset_token)
        ).lock.first
        result = reset_with(challenge)
      end
      result
    end

    private

    attr_reader :brand, :reset_token, :password, :password_confirmation, :ip_address, :user_agent

    def reset_with(challenge)
      return failure(:invalid_token) if challenge.blank? || challenge.consumed? || challenge.expired?

      identity_identifier = challenge.identity_identifier
      credential = recoverable_credential(identity_identifier)
      return failure(:invalid_token) if credential.blank?

      unless password == password_confirmation && PasswordEngine.valid?(password:)
        # Keep the authorization live so the caller can retry with a valid password.
        audit(identity_identifier, credential, result: :failed, failure_stage: "replacement")
        return failure(:invalid_password)
      end

      PasswordEngine.set!(credential:, password:)
      challenge.consume!
      expire_sibling_challenges(identity_identifier)
      revoked = revoke_credential_sessions(identity_identifier.user, credential)
      audit(identity_identifier, credential, result: :succeeded, revoked_session_count: revoked)

      Result.new(true, nil, revoked)
    end

    def recoverable_credential(identity_identifier)
      return if identity_identifier.blank? || identity_identifier.deleted_at.present?

      identity_identifier.credentials.kept.find_by(kind: :password, status: :active)
    end

    def expire_sibling_challenges(identity_identifier)
      OtpChallenge.active.where(
        brand:,
        identity_identifier:,
        kind: [ RECOVERY_KIND, RESET_KIND ]
      ).update_all(consumed_at: Time.current, updated_at: Time.current)
    end

    def revoke_credential_sessions(user, credential)
      Session.active.where(user:, credential:)
        .update_all(revoked_at: Time.current, updated_at: Time.current)
    end

    def audit(identity_identifier, credential, result:, revoked_session_count: nil, failure_stage: nil)
      PasswordAudit.record!(
        brand:,
        purpose: PURPOSE,
        result:,
        identifier: identity_identifier.normalized_value,
        identifier_kind: identity_identifier.kind,
        ip_address:,
        user_agent:,
        user: identity_identifier.user,
        identity_identifier:,
        credential:,
        metadata: { revoked_session_count:, failure_stage: }.compact
      )
    end

    def failure(error)
      Result.new(false, error, 0)
    end
  end
end
