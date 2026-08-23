module Identity
  class EmailChangeVerifier
    Result = Data.define(:success?, :error, :revoked_session_count)
    MAX_ATTEMPTS = 5

    def self.call(...)
      new(...).call
    end

    def initialize(session:, email:, code:, ip_address: nil, user_agent: nil)
      @session = session
      @email_input = email
      @code = code.to_s
      @ip_address = ip_address
      @user_agent = user_agent
    end

    def call
      return failure(:invalid_code) unless eligible_credential?

      replacement = LoginIdentifier.call(email_input)
      return failure(:invalid_code) unless replacement&.kind == :email

      new_email = replacement.normalized_value
      result = nil
      ActiveRecord::Base.transaction do
        AuthenticationLock.with_lock(
          brand: session.brand,
          purpose: "email_change_confirmation",
          identifier: new_email,
          ip_address:
        ) do
          result = verify_under_lock(new_email)
        end
      end
      result
    rescue ActiveRecord::RecordNotUnique
      record_unique_conflict(new_email)
    end

    private

    attr_reader :session, :email_input, :code, :ip_address, :user_agent

    def verify_under_lock(new_email)
      challenge = latest_challenge(new_email)
      return failed_without_challenge(new_email) if challenge.blank?

      challenge.lock!
      identifier.lock!
      credential.lock!
      return failed_without_challenge(new_email) if challenge.consumed? || challenge.expired?
      return locked(challenge, new_email) if challenge.attempt_count >= MAX_ATTEMPTS
      return wrong_code(challenge, new_email) unless challenge.code_matches?(code)
      return unavailable(challenge, new_email) if email_owned?(new_email)

      old_email = identifier.normalized_value
      identifier.update!(normalized_value: new_email, verified_at: Time.current, last_seen_at: Time.current)
      consume_identifier_challenges
      revoked_count = revoke_other_credential_sessions
      audit("succeeded", old_email:, new_email:, revoked_session_count: revoked_count)
      Result.new(true, nil, revoked_count)
    end

    def wrong_code(challenge, new_email)
      challenge.increment!(:attempt_count)
      outcome = challenge.attempt_count >= MAX_ATTEMPTS ? "locked" : "failed"
      challenge.consume! if outcome == "locked"
      audit(outcome, old_email: identifier.normalized_value, new_email:)
      failure(:invalid_code)
    end

    def locked(challenge, new_email)
      challenge.consume!
      audit("locked", old_email: identifier.normalized_value, new_email:)
      failure(:invalid_code)
    end

    def unavailable(challenge, new_email)
      challenge.consume!
      audit("unavailable", old_email: identifier.normalized_value, new_email:)
      failure(:email_change_unavailable)
    end

    def failed_without_challenge(new_email)
      OtpChallenge.digest_code(code)
      audit("failed", old_email: identifier.normalized_value, new_email:)
      failure(:invalid_code)
    end

    def latest_challenge(new_email)
      OtpChallenge.active.where(
        brand: session.brand,
        identity_identifier: identifier,
        kind: :email_change,
        identifier: new_email
      ).where("metadata ->> 'session_id' = ?", session.id.to_s).order(created_at: :desc).first
    end

    def consume_identifier_challenges
      OtpChallenge.active.where(identity_identifier: identifier)
        .update_all(consumed_at: Time.current, updated_at: Time.current)
    end

    def revoke_other_credential_sessions
      Session.active.where(user: session.user, credential:).where.not(id: session.id)
        .update_all(revoked_at: Time.current, updated_at: Time.current)
    end

    def email_owned?(new_email)
      IdentityIdentifier.kept.email.where(normalized_value: new_email).where.not(id: identifier.id).exists?
    end

    def eligible_credential?
      credential&.password? && credential.active? && credential.deleted_at.nil? &&
        identifier&.email? && identifier.deleted_at.nil? && credential.user_id == session.user_id
    end

    def credential
      @credential ||= session.credential
    end

    def identifier
      @identifier ||= credential&.identity_identifier
    end

    def audit(outcome, old_email:, new_email:, revoked_session_count: nil)
      AuthAttempt.create!(
        brand: session.brand,
        user: session.user,
        identity_identifier: identifier,
        credential:,
        kind: :email_otp,
        result: outcome == "succeeded" ? :succeeded : :failed,
        identifier: new_email,
        ip_address:,
        user_agent:,
        metadata: { purpose: "email_change" }
      )
      SecurityEvent.create!(
        brand: session.brand,
        user: session.user,
        event_type: "auth.email_change.#{outcome}",
        severity: outcome == "succeeded" ? :info : :warning,
        ip_address:,
        user_agent:,
        metadata: {
          old_identifier_last4: old_email.last(4),
          new_identifier_last4: new_email.last(4),
          revoked_session_count:
        }.compact
      )
    end

    def record_unique_conflict(new_email)
      ActiveRecord::Base.transaction do
        challenge = latest_challenge(new_email)
        challenge&.with_lock { challenge.consume! unless challenge.consumed? }
        audit("unavailable", old_email: identifier.reload.normalized_value, new_email:)
      end
      failure(:email_change_unavailable)
    end

    def failure(error)
      Result.new(false, error, 0)
    end
  end
end
