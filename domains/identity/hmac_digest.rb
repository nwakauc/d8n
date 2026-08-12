module Identity
  class HmacDigest
    def self.call(purpose:, value:)
      key = Rails.application.key_generator.generate_key("d8n:#{purpose}:v1", 32)
      OpenSSL::HMAC.hexdigest("SHA256", key, value.to_s)
    end
  end
end
