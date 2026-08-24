module Identity
  class EmailChangeRequester
    Result = Data.define(:success?, :error, :retry_after)
    PURPOSE = "email_change".freeze
    EXPIRES_IN = 10.minutes
    ACCOUNT_COOLDOWN = 60.seconds
    ACCOUNT_WINDOW = 10.minutes
    ACCOUNT_LIMIT = 5

    def self.call(...)
      new(...).call
    end

    def initialize(session:, email:, current_password:, ip_address: nil, user_agent: nil)
      @session = session
      @email_input = email
      @current_password = current_password
      @ip_address = ip_address
      @user_agent = user_agent
    end

    def call
      return failure(:password_credential_required) unless eligible_credential?

      replacement = LoginIdentifier.call(email_input)
      return unavailable unless replacement&.kind == :email

      result = nil
      ActiveRecord::Base.transaction do
        AuthenticationLock.with_lock(
          brand: session.brand,
          purpose: PURPOSE,
          identifier: identifier.normalized_value,
          ip_address:
        ) do
          result = request_under_lock(replacement.normalized_value)
        end
      end
      enqueue_delivery
      result
    end

    private

    attr_reader :session, :email_input, :current_password, :ip_address, :user_agent

    def request_under_lock(new_email)
      throttle = PasswordThrottle.call(
        brand: session.brand,
        purpose: PURPOSE,
        identifier: identifier.normalized_value,
        ip_address:
      )
      if throttle.throttled?
        audit_password(result: :throttled, retry_after: throttle.retry_after)
        return failure(:rate_limited, retry_after: throttle.retry_after)
      end

      unless PasswordEngine.matches?(credential:, password: current_password)
        audit_password(result: :failed, failure_stage: "reauthentication")
        return failure(:invalid_current_password)
      end

      return unavailable(new_email, audit: true) if new_email == identifier.normalized_value || email_owned?(new_email)
      if (account_throttle = account_throttle_result)
        audit_event("throttled", severity: :warning, new_email:, retry_after: account_throttle.last)
        return failure(account_throttle.first, retry_after: account_throttle.last)
      end

      request_code(new_email)
    end

    def request_code(new_email)
      result = nil
      OtpThrottleLock.with_lock(
        brand: session.brand,
        identifier: new_email,
        kind: :email_change,
        ip_address:
      ) do
        throttle = OtpThrottle.call(
          brand: session.brand,
          identifier: new_email,
          kind: :email_change,
          ip_address:
        )
        result = if throttle.throttled?
          audit_event("throttled", severity: :warning, retry_after: throttle.retry_after)
          error = throttle.scope == :identifier_cooldown ? :verification_resend_too_soon : :verification_rate_limited
          failure(error, retry_after: throttle.retry_after)
        else
          create_and_deliver(new_email)
        end
      end
      result
    end

    def create_and_deliver(new_email)
      code = OtpCode.generate
      challenge = OtpChallenge.create!(
        brand: session.brand,
        identity_identifier: identifier,
        kind: :email_change,
        identifier: new_email,
        code_digest: OtpChallenge.digest_code(code),
        delivery_code: code,
        expires_at: EXPIRES_IN.from_now,
        ip_address:,
        user_agent:,
        metadata: { purpose: PURPOSE, session_id: session.id }
      )
      expire_older_challenges(except: challenge)

      unless Notifications::Email.configured?(brand: session.brand)
        challenge.consume!
        audit_event("delivery_failed", severity: :warning, challenge:)
        return failure(:delivery_unavailable)
      end

      @challenge_to_deliver = challenge
      audit_event("requested", challenge:)
      Result.new(true, nil, nil)
    end

    def expire_older_challenges(except:)
      OtpChallenge.active.where(
        brand: session.brand,
        identity_identifier: identifier,
        kind: :email_change
      ).where.not(id: except.id).update_all(consumed_at: Time.current, updated_at: Time.current)
    end

    def enqueue_delivery
      return if @challenge_to_deliver.nil?

      Notifications::DeliverChallengeJob.perform_later(@challenge_to_deliver.id)
    end

    def email_owned?(new_email)
      IdentityIdentifier.kept.email.where(normalized_value: new_email).where.not(id: identifier.id).exists?
    end

    def account_throttle_result
      attempts = OtpChallenge.where(
        brand: session.brand,
        identity_identifier: identifier,
        kind: :email_change,
        created_at: ACCOUNT_WINDOW.ago..
      ).order(:created_at)
      latest = attempts.last
      cooldown = latest && (latest.created_at + ACCOUNT_COOLDOWN - Time.current).ceil
      return [ :verification_resend_too_soon, [ cooldown, 1 ].max ] if cooldown&.positive?
      return if attempts.count < ACCOUNT_LIMIT

      [ :verification_rate_limited, [ (attempts.first.created_at + ACCOUNT_WINDOW - Time.current).ceil, 1 ].max ]
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

    def audit_password(result:, retry_after: nil, failure_stage: nil)
      PasswordAudit.record!(
        brand: session.brand,
        purpose: PURPOSE,
        result:,
        identifier: identifier.normalized_value,
        identifier_kind: :email,
        ip_address:,
        user_agent:,
        user: session.user,
        identity_identifier: identifier,
        credential:,
        retry_after:,
        metadata: { failure_stage: }.compact
      )
    end

    def audit_event(outcome, severity: :info, challenge: nil, new_email: nil, retry_after: nil)
      SecurityEvent.create!(
        brand: session.brand,
        user: session.user,
        event_type: "auth.email_change.#{outcome}",
        severity:,
        ip_address:,
        user_agent:,
        metadata: {
          challenge_id: challenge&.id,
          old_identifier_last4: identifier.normalized_value.last(4),
          new_identifier_last4: (challenge&.identifier || new_email)&.last(4),
          retry_after:
        }.compact
      )
    end

    def unavailable(new_email = nil, audit: false)
      audit_event("unavailable", severity: :warning, new_email:) if audit
      failure(:email_change_unavailable)
    end

    def failure(error, retry_after: nil)
      Result.new(false, error, retry_after)
    end
  end
end
