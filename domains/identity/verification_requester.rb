module Identity
  class VerificationRequester
    Result = Data.define(:success?, :error, :retry_after)
    EXPIRES_IN = 10.minutes
    SUPPORTED_KINDS = %w[ phone email ].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(user:, brand:, kind:, ip_address: nil, user_agent: nil)
      @user = user
      @brand = brand
      @kind = kind.to_s
      @ip_address = ip_address
      @user_agent = user_agent
    end

    def call
      return failure(:invalid_kind) unless SUPPORTED_KINDS.include?(kind)

      identity_identifier = owned_identifier
      return generic_success if identity_identifier.blank? || identity_identifier.verified_at.present?

      request_code(identity_identifier)
    end

    private

    attr_reader :user, :brand, :kind, :ip_address, :user_agent

    def request_code(identity_identifier)
      result = nil

      OtpChallenge.transaction do
        OtpThrottleLock.with_lock(
          brand:,
          identifier: identity_identifier.normalized_value,
          kind: challenge_kind,
          ip_address:
        ) do
          throttle = OtpThrottle.call(
            brand:,
            identifier: identity_identifier.normalized_value,
            kind: challenge_kind,
            ip_address:
          )
          result = if throttle.throttled?
            record_attempt(identity_identifier, result: :throttled, retry_after: throttle.retry_after)
            error = throttle.scope == :identifier_cooldown ? :verification_resend_too_soon : :verification_rate_limited
            failure(error, retry_after: throttle.retry_after)
          else
            create_and_deliver(identity_identifier)
          end
        end
      end

      # Enqueue only after the transaction + advisory lock commit/release, so the
      # code is durably visible before the worker reads it and no provider I/O runs
      # under the lock.
      enqueue_delivery

      result
    end

    def create_and_deliver(identity_identifier)
      code = OtpCode.generate
      challenge = OtpChallenge.create!(
        brand:,
        identity_identifier:,
        kind: challenge_kind,
        identifier: identity_identifier.normalized_value,
        code_digest: OtpChallenge.digest_code(code),
        delivery_code: code,
        expires_at: EXPIRES_IN.from_now,
        ip_address:,
        user_agent:,
        metadata: { purpose: "identifier_verification" }
      )
      expire_older_challenges(identity_identifier, except: challenge)

      # Fail closed synchronously on misconfiguration (deterministic, no network):
      # the caller owns this identifier, so a 503 here leaks nothing and keeps the
      # existing "delivery_unavailable" contract without enqueuing a doomed job.
      unless delivery_configured?(identity_identifier)
        challenge.consume!
        record_event(identity_identifier, "delivery_failed", severity: :warning, challenge:)
        return failure(:delivery_unavailable)
      end

      @challenge_to_deliver = challenge
      record_event(identity_identifier, "requested", challenge:)
      generic_success(retry_after: OtpThrottle::IDENTIFIER_COOLDOWN.to_i)
    end

    def delivery_configured?(identity_identifier)
      identity_identifier.phone? ? Notifications::Sms.configured? : Notifications::Email.configured?(brand:)
    end

    def enqueue_delivery
      return if @challenge_to_deliver.nil?

      Notifications::DeliverChallengeJob.perform_later(@challenge_to_deliver.id)
    end

    def expire_older_challenges(identity_identifier, except:)
      OtpChallenge.active.where(
        brand:,
        identity_identifier:,
        kind: challenge_kind
      ).where.not(id: except.id).update_all(consumed_at: Time.current, updated_at: Time.current)
    end

    def owned_identifier
      user.identity_identifiers.kept.find_by(kind:)
    end

    def challenge_kind
      "#{kind}_verification"
    end

    def attempt_kind
      kind == "phone" ? :phone_otp : :email_otp
    end

    def record_attempt(identity_identifier, result:, retry_after: nil)
      AuthAttempt.create!(
        brand:,
        user:,
        identity_identifier:,
        kind: attempt_kind,
        result:,
        identifier: identity_identifier.normalized_value,
        ip_address:,
        user_agent:,
        metadata: { purpose: "identifier_verification", retry_after: }.compact
      )
      record_event(identity_identifier, result.to_s, severity: :warning, retry_after:)
    end

    def record_event(identity_identifier, outcome, severity: :info, challenge: nil, retry_after: nil)
      SecurityEvent.create!(
        brand:,
        user:,
        event_type: "auth.#{kind}_verification.#{outcome}",
        severity:,
        ip_address:,
        user_agent:,
        metadata: {
          challenge_id: challenge&.id,
          identifier_kind: kind,
          identifier_last4: identity_identifier.normalized_value.last(4),
          retry_after:
        }.compact
      )
    end

    def generic_success(retry_after: nil)
      Result.new(true, nil, retry_after)
    end

    def failure(error, retry_after: nil)
      Result.new(false, error, retry_after)
    end
  end
end
