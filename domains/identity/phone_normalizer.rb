module Identity
  class PhoneNormalizer
    MIN_DIGITS = 8
    MAX_DIGITS = 15

    def self.call(value)
      new(value).call
    end

    def initialize(value)
      @value = value
    end

    def call
      digits = value.to_s.gsub(/\D/, "")
      return nil unless digits.length.between?(MIN_DIGITS, MAX_DIGITS)

      digits
    end

    private

    attr_reader :value
  end
end
