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
            failure(:rate_limited, retry_after: throttle.retry_after)
          else
            create_and_deliver(identity_identifier)
          end
        end
      end

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
        expires_at: EXPIRES_IN.from_now,
        ip_address:,
        user_agent:,
        metadata: { purpose: "identifier_verification" }
      )
      expire_older_challenges(identity_identifier, except: challenge)

      delivery = deliver(identity_identifier, code, challenge)
      unless delivery.success?
        challenge.consume!
        record_event(identity_identifier, "delivery_failed", severity: :warning, challenge:)
        return failure(:delivery_unavailable)
      end

      record_event(identity_identifier, "requested", challenge:)
      generic_success
    end

    def expire_older_challenges(identity_identifier, except:)
      OtpChallenge.active.where(
        brand:,
        identity_identifier:,
        kind: challenge_kind
      ).where.not(id: except.id).update_all(consumed_at: Time.current, updated_at: Time.current)
    end

    def deliver(identity_identifier, code, challenge)
      metadata = { purpose: "identifier_verification", challenge_id: challenge.id }
      if kind == "phone"
        Notifications::SmsSender.call(
          brand:,
          user:,
          recipient: identity_identifier.normalized_value,
          body: "#{brand.name} verification code: #{code}",
          metadata:
        )
      else
        Notifications::EmailSender.call(
          brand:,
          user:,
          recipient: identity_identifier.normalized_value,
          code:,
          metadata:
        )
      end
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

    def generic_success
      Result.new(true, nil, nil)
    end

    def failure(error, retry_after: nil)
      Result.new(false, error, retry_after)
    end
  end
end
