module Identity
  class AuthenticationLock
    def self.with_lock(brand:, purpose:, identifier:, ip_address:)
      values = [ "identifier:#{brand.id}:#{purpose}:#{identifier}" ]
      values << "ip:#{brand.id}:#{purpose}:#{ip_address}" if ip_address.present?

      values.map { |value| HmacDigest.call(purpose: "authentication-lock", value:) }.sort.each do |key|
        quoted_key = ActiveRecord::Base.connection.quote(key)
        ActiveRecord::Base.connection.execute(
          "SELECT pg_advisory_xact_lock(hashtextextended(#{quoted_key}, 0))"
        )
      end

      yield
    end
  end
end
