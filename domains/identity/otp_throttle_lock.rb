module Identity
  class OtpThrottleLock
    def self.with_lock(brand:, identifier:, kind:, ip_address:)
      keys = [ lock_key(brand:, scope: "identifier", value: "#{kind}:#{identifier}") ]
      keys << lock_key(brand:, scope: "ip", value: ip_address) if ip_address.present?

      keys.sort.each do |key|
        quoted_key = ActiveRecord::Base.connection.quote(key)
        ActiveRecord::Base.connection.execute(
          "SELECT pg_advisory_xact_lock(hashtextextended(#{quoted_key}, 0))"
        )
      end

      yield
    end

    def self.lock_key(brand:, scope:, value:)
      digest = HmacDigest.call(purpose: "otp-throttle-lock", value: "#{brand.id}:#{scope}:#{value}")
      "otp:#{brand.id}:#{scope}:#{digest}"
    end
    private_class_method :lock_key
  end
end
