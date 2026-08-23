module Identity
  # Step 1 of signed-out password recovery: accept an identifier and, only when it
  # maps to an eligible verified identity with a recoverable password credential,
  # deliver a single-use recovery code through the existing OTP delivery channel.
  #
  # This service is account-enumeration resistant by construction: EVERY outcome —
  # unknown identifier, unverified identifier, no password credential, no membership
  # in the requesting brand, throttled, or delivery failure — returns the same
  # generic success. The caller (controller) must render an identical neutral
  # response regardless. Throttling therefore manifests as silent non-delivery, not
  # as a 429, so an attacker cannot distinguish an eligible target by its rate-limit
  # behavior. Recovery is only offered through an already-verified identifier
  # (ADR 0012): an unverified identifier can authenticate with its password but can
  # never become a password-reset channel.
  class RecoveryRequester
    Result = Data.define(:success?)
    CODE_EXPIRES_IN = 10.minutes
    CHALLENGE_KIND = "password_recovery"

    def self.call(...)
      new(...).call
    end

    def initialize(brand:, identifier:, ip_address: nil, user_agent: nil)
      @brand = brand
      @identifier_input = identifier
      @ip_address = ip_address
      @user_agent = user_agent
    end

    def call
      return generic_success unless active_brand?

      login_identifier = LoginIdentifier.call(identifier_input)
      return generic_success if login_identifier.blank?
      return generic_success unless AuthPolicy.enabled?(brand:, method: login_identifier.auth_method)

      identity_identifier = eligible_identifier(login_identifier)
      return generic_success if identity_identifier.blank?

      credential = recoverable_credential(identity_identifier)
      return generic_success if credential.blank?

      deliver_recovery_code(identity_identifier)
      generic_success
    end

    private

    attr_reader :brand, :identifier_input, :ip_address, :user_agent

    # Eligibility is intentionally identity-level, not brand-membership-state level.
    # A suspended user or a `left`/closed HookUs member may still hold a valid D8N
    # identity and reset the D8N-wide password; login independently re-checks
    # lifecycle and membership, so recovery never silently restores access. We do
    # require a kept membership in the *requesting* brand so one brand cannot be used
    # to send recovery codes to identifiers that only belong to another brand.
    def eligible_identifier(login_identifier)
      identity_identifier = IdentityIdentifier.kept.find_by(
        kind: login_identifier.kind,
        normalized_value: login_identifier.normalized_value
      )
      return if identity_identifier.blank?
      return if identity_identifier.verified_at.blank?

      user = identity_identifier.user
      return if user.blank? || user.deleted_at.present?
      return unless BrandMembership.kept.exists?(user:, brand:)

      identity_identifier
    end

    def recoverable_credential(identity_identifier)
      identity_identifier.credentials.kept.find_by(kind: :password, status: :active)
    end

    def deliver_recovery_code(identity_identifier)
      OtpChallenge.transaction do
        OtpThrottleLock.with_lock(
          brand:,
          identifier: identity_identifier.normalized_value,
          kind: CHALLENGE_KIND,
          ip_address:
        ) do
          throttle = OtpThrottle.call(
            brand:,
            identifier: identity_identifier.normalized_value,
            kind: CHALLENGE_KIND,
            ip_address:
          )
          if throttle.throttled?
            record_event(identity_identifier, "throttled", severity: :warning, retry_after: throttle.retry_after)
          else
            create_and_deliver(identity_identifier)
          end
        end
      end

      # Enqueue the provider call only AFTER the transaction + advisory lock have
      # committed/released, so the code is durably visible before the worker reads
      # it and no network I/O happens while the lock is held.
      enqueue_delivery
    end

    def create_and_deliver(identity_identifier)
      code = OtpCode.generate
      challenge = OtpChallenge.create!(
        brand:,
        identity_identifier:,
        kind: CHALLENGE_KIND,
        identifier: identity_identifier.normalized_value,
        code_digest: OtpChallenge.digest_code(code),
        delivery_code: code,
        expires_at: CODE_EXPIRES_IN.from_now,
        ip_address:,
        user_agent:,
        metadata: { purpose: "password_recovery" }
      )
      expire_older_challenges(identity_identifier, except: challenge)

      # Fail closed synchronously on misconfiguration (deterministic, no network):
      # the neutral recovery contract stays silent, and no doomed job is enqueued.
      unless delivery_configured?(identity_identifier)
        challenge.consume!
        record_event(identity_identifier, "delivery_failed", severity: :warning, challenge:)
        return
      end

      @challenge_to_deliver = challenge
      record_event(identity_identifier, "requested", challenge:)
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
        kind: CHALLENGE_KIND
      ).where.not(id: except.id).update_all(consumed_at: Time.current, updated_at: Time.current)
    end

    def record_event(identity_identifier, outcome, severity: :info, challenge: nil, retry_after: nil)
      SecurityEvent.create!(
        brand:,
        user: identity_identifier.user,
        event_type: "auth.password_recovery.#{outcome}",
        severity:,
        ip_address:,
        user_agent:,
        metadata: {
          challenge_id: challenge&.id,
          identifier_kind: identity_identifier.kind,
          identifier_last4: identity_identifier.normalized_value.last(4),
          retry_after:
        }.compact
      )
    end

    def active_brand?
      brand.present? && brand.active? && brand.deleted_at.nil?
    end

    def generic_success
      Result.new(true)
    end
  end
end
