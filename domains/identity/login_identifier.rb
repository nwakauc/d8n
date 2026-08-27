module Identity
  class LoginIdentifier
    Result = Data.define(:kind, :normalized_value, :auth_method, :lookup_values)

    EMAIL_PATTERN = /\A[^\s@]+@[^\s@]+\.[^\s@]+\z/
    MAX_EMAIL_LENGTH = 254

    def self.call(value, brand: nil)
      raw_value = value.to_s.strip
      return if raw_value.blank?

      raw_value.include?("@") ? email_result(raw_value) : phone_result(raw_value, brand:)
    end

    def self.email_result(value)
      normalized = value.downcase
      return unless normalized.length <= MAX_EMAIL_LENGTH && EMAIL_PATTERN.match?(normalized)

      Result.new(:email, normalized, :email_password, [ normalized ])
    end
    private_class_method :email_result

    def self.phone_result(value, brand:)
      calling_code = PhonePolicy.country_calling_code(brand:)
      normalized = PhoneNormalizer.call(value, country_calling_code: calling_code)
      return if normalized.blank?

      local_alias = national_alias(normalized, calling_code:)
      Result.new(:phone, normalized, :phone_password, [ normalized, local_alias ].compact.uniq)
    end
    private_class_method :phone_result

    def self.national_alias(normalized, calling_code:)
      return if calling_code.blank? || !normalized.start_with?(calling_code)

      "0#{normalized.delete_prefix(calling_code)}"
    end
    private_class_method :national_alias
  end
end
