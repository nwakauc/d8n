module Identity
  class AuthPolicy
    SUPPORTED_METHODS = %w[
      phone_password
      email_password
      google
    ].freeze
    IMPLEMENTED_METHODS = %w[ phone_password email_password ].freeze

    def self.enabled?(brand:, method:)
      brand.present? && brand.auth_methods.include?(method.to_s)
    end

    def self.available_methods(brand:)
      return [] if brand.blank?

      brand.auth_methods & IMPLEMENTED_METHODS
    end
  end
end
