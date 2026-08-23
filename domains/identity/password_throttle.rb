module Identity
  class PasswordThrottle
    Result = Data.define(:throttled?, :scope, :retry_after)

    POLICIES = {
      "password_registration" => {
        window: 1.hour,
        identifier_limit: 5,
        ip_limit: 20
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
        relation: failed_scope.where(identifier:),
        window: policy.fetch(:window),
        limit: policy.fetch(:identifier_limit)
      )
    end

    def ip_result(policy)
      return if ip_address.blank?

      throttled_result(
        scope: :ip,
        relation: failed_scope.where(ip_address:),
        window: policy.fetch(:window),
        limit: policy.fetch(:ip_limit)
      )
    end

    def failed_scope
      scope = AuthAttempt.where(brand:, kind: :password, result: :failed)
        .where("metadata ->> 'purpose' = ?", purpose)
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
