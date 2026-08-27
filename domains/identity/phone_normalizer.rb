module Identity
  class PhoneNormalizer
    MIN_DIGITS = 8
    MAX_DIGITS = 15

    def self.call(value, country_calling_code: nil)
      new(value, country_calling_code:).call
    end

    def initialize(value, country_calling_code: nil)
      @value = value
      @country_calling_code = country_calling_code.to_s
    end

    def call
      digits = value.to_s.gsub(/\D/, "")
      digits = normalize_international_prefix(digits)
      digits = normalize_national_prefix(digits)
      return nil unless digits.length.between?(MIN_DIGITS, MAX_DIGITS)

      digits
    end

    private

    attr_reader :value, :country_calling_code

    def normalize_international_prefix(digits)
      value.to_s.strip.start_with?("00") ? digits.delete_prefix("00") : digits
    end

    def normalize_national_prefix(digits)
      return digits if country_calling_code.blank? || digits.start_with?(country_calling_code)
      return digits unless digits.start_with?("0")

      "#{country_calling_code}#{digits.delete_prefix('0')}"
    end
  end
end
