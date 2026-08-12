module Identity
  class OtpThrottle
    Result = Data.define(:throttled?, :scope, :retry_after)

    PHONE_COOLDOWN = 60.seconds
    PHONE_WINDOW = 10.minutes
    PHONE_LIMIT = 5
    IP_WINDOW = 10.minutes
    IP_LIMIT = 20

    def self.call(...)
      new(...).call
    end

    def initialize(brand:, identifier:, ip_address:)
      @brand = brand
      @identifier = identifier
      @ip_address = ip_address
    end

    def call
      phone_cooldown_result || phone_window_result || ip_window_result || allowed_result
    end

    private

    attr_reader :brand, :identifier, :ip_address

    def phone_cooldown_result
      latest = phone_scope.order(created_at: :desc).first
      return if latest.blank?

      retry_after = retry_after_for(latest.created_at, PHONE_COOLDOWN)
      return if retry_after <= 0

      Result.new(true, :phone_cooldown, positive_retry_after(retry_after))
    end

    def phone_window_result
      throttled_window_result(
        scope: :phone_window,
        relation: phone_scope,
        window: PHONE_WINDOW,
        limit: PHONE_LIMIT
      )
    end

    def ip_window_result
      return if ip_address.blank?

      throttled_window_result(
        scope: :ip_window,
        relation: base_scope.where(ip_address:),
        window: IP_WINDOW,
        limit: IP_LIMIT
      )
    end

    def throttled_window_result(scope:, relation:, window:, limit:)
      window_start = window.ago
      attempts = relation.where(created_at: window_start..).order(:created_at)
      return if attempts.count < limit

      Result.new(true, scope, positive_retry_after(retry_after_for(attempts.first.created_at, window)))
    end

    def base_scope
      OtpChallenge.where(brand:, kind: :phone_otp)
    end

    def phone_scope
      base_scope.where(identifier:)
    end

    def retry_after_for(timestamp, duration)
      (timestamp + duration - Time.current).ceil
    end

    def positive_retry_after(seconds)
      [ seconds, 1 ].max
    end

    def allowed_result
      Result.new(false, nil, nil)
    end
  end
end
