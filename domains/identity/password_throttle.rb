module Identity
  class PasswordThrottle
    Result = Data.define(:throttled?, :scope, :retry_after)

    POLICIES = {
      # Registration is the one purpose where a SUCCESSFUL attempt is itself the
      # abuse signal (an attacker's distinct new accounts all "succeed"). Every
      # other purpose counts failures only, so a legitimate member logging in or
      # changing their password repeatedly is never throttled by their own
      # success. See #counted_attempts_scope.
      #
      # Also platform-wide (`brand_scoped: false`): IdentityIdentifier has no
      # brand_id and is globally unique across D8N (app/models/identity_identifier.rb),
      # so there is no legitimate "separate per-brand registration" with the same
      # identifier to protect — and a brand-scoped IP counter would let an
      # attacker multiply their registration budget by switching Host between
      # brands. See #counted_attempts_scope.
      "password_registration" => {
        window: 1.hour,
        identifier_limit: 5,
        ip_limit: 20,
        count_successes: true,
        brand_scoped: false
      },
      "password_login" => {
        window: 15.minutes,
        identifier_limit: 10,
        ip_limit: 50
      },
      "password_change" => {
        window: 15.minutes,
        identifier_limit: 5,
        ip_limit: 20
      },
      "email_change" => {
        window: 15.minutes,
        identifier_limit: 5,
        ip_limit: 20
      }
    }.freeze

    def self.call(...)
      new(...).call
    end

    def initialize(brand:, purpose:, identifier:, ip_address:)
      @brand = brand
      @purpose = purpose.to_s
      @identifier = identifier
      @ip_address = ip_address
    end

    def call
      policy = POLICIES.fetch(purpose)
      identifier_result(policy) || ip_result(policy) || Result.new(false, nil, nil)
    end

    private

    attr_reader :brand, :purpose, :identifier, :ip_address

    def identifier_result(policy)
      throttled_result(
        scope: :identifier,
        relation: counted_attempts_scope(policy).where(identifier:),
        window: policy.fetch(:window),
        limit: policy.fetch(:identifier_limit)
      )
    end

    def ip_result(policy)
      return if ip_address.blank?

      throttled_result(
        scope: :ip,
        relation: counted_attempts_scope(policy).where(ip_address:),
        window: policy.fetch(:window),
        limit: policy.fetch(:ip_limit)
      )
    end

    # Every purpose always counts `failed`; `password_registration` additionally
    # counts `succeeded` (see POLICIES) because an attacker's account-creation
    # attempts routinely succeed — a throttle that only watches for failure would
    # never see them. Every purpose except `password_registration` is brand-scoped
    # (default `true`), matching each purpose's own resource scope (credentials
    # and sessions are brand-bound).
    def counted_attempts_scope(policy)
      results = policy.fetch(:count_successes, false) ? %w[ failed succeeded ] : %w[ failed ]
      scope = AuthAttempt.where(kind: :password, result: results)
        .where("metadata ->> 'purpose' = ?", purpose)
      scope = scope.where(brand:) if policy.fetch(:brand_scoped, true)
      return scope unless %w[ password_change email_change ].include?(purpose)

      scope.where("metadata ->> 'failure_stage' = ?", "reauthentication")
    end

    def throttled_result(scope:, relation:, window:, limit:)
      window_start = window.ago
      attempts = relation.where(created_at: window_start..).order(:created_at)
      return if attempts.count < limit

      retry_after = (attempts.first.created_at + window - Time.current).ceil
      Result.new(true, scope, [ retry_after, 1 ].max)
    end
  end
end
