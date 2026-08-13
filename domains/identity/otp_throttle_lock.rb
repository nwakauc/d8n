module Identity
  class OtpThrottleLock
    def self.with_lock(brand:, identifier:, ip_address:)
      keys = [ "phone:#{brand.id}:#{identifier}" ]
      keys << "ip:#{brand.id}:#{ip_address}" if ip_address.present?

      keys.sort.each do |key|
        quoted_key = ActiveRecord::Base.connection.quote(key)
        ActiveRecord::Base.connection.execute(
          "SELECT pg_advisory_xact_lock(hashtextextended(#{quoted_key}, 0))"
        )
      end

      yield
    end
  end
end
