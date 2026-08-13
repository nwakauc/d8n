module Identity
  class LoginIdentifier
    Result = Data.define(:kind, :normalized_value, :auth_method)

    EMAIL_PATTERN = /\A[^\s@]+@[^\s@]+\.[^\s@]+\z/
    MAX_EMAIL_LENGTH = 254

    def self.call(value)
      raw_value = value.to_s.strip
      return if raw_value.blank?

      raw_value.include?("@") ? email_result(raw_value) : phone_result(raw_value)
    end

    def self.email_result(value)
      normalized = value.downcase
      return unless normalized.length <= MAX_EMAIL_LENGTH && EMAIL_PATTERN.match?(normalized)

      Result.new(:email, normalized, :email_password)
    end
    private_class_method :email_result

    def self.phone_result(value)
      normalized = PhoneNormalizer.call(value)
      return if normalized.blank?

      Result.new(:phone, normalized, :phone_password)
    end
    private_class_method :phone_result
  end
end
