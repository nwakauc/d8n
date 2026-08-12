module Identity
  class OtpCode
    DIGITS = 6

    def self.generate
      SecureRandom.random_number(10**DIGITS).to_s.rjust(DIGITS, "0")
    end
  end
end
