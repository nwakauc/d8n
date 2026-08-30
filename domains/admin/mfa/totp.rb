require "openssl"
require "cgi"

module Admin
  module Mfa
    module Totp
      PERIOD = 30
      DIGITS = 6
      SECRET_BYTES = 20
      ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".freeze

      module_function

      def generate_secret
        encode_base32(SecureRandom.random_bytes(SECRET_BYTES))
      end

      def valid?(secret:, code:, at: Time.current, drift: 1)
        supplied = code.to_s.gsub(/\s+/, "")
        return false unless supplied.match?(/\A\d{#{DIGITS}}\z/)

        counter = at.to_i / PERIOD
        (-drift..drift).any? do |offset|
          expected = code_at(secret:, counter: counter + offset)
          ActiveSupport::SecurityUtils.secure_compare(expected, supplied)
        end
      rescue ArgumentError
        false
      end

      def provisioning_uri(secret:, account:)
        issuer = "D8N HQ"
        label = CGI.escape("#{issuer}:#{account}")
        "otpauth://totp/#{label}?secret=#{secret}&issuer=#{CGI.escape(issuer)}&algorithm=SHA1&digits=#{DIGITS}&period=#{PERIOD}"
      end

      def code_at(secret:, counter:)
        digest = OpenSSL::HMAC.digest("SHA1", decode_base32(secret), [ counter ].pack("Q>"))
        offset = digest.getbyte(-1) & 0x0f
        binary = digest.byteslice(offset, 4).unpack1("N") & 0x7fffffff
        (binary % (10**DIGITS)).to_s.rjust(DIGITS, "0")
      end

      def encode_base32(bytes)
        bits = bytes.unpack1("B*")
        bits.scan(/.{1,5}/).map { |chunk| ALPHABET[chunk.ljust(5, "0").to_i(2)] }.join
      end
      private_class_method :encode_base32

      def decode_base32(value)
        normalized = value.to_s.upcase.delete("= \t\r\n-")
        raise ArgumentError, "invalid base32" unless normalized.match?(/\A[A-Z2-7]+\z/)

        bits = normalized.chars.map { |char| ALPHABET.index(char).to_s(2).rjust(5, "0") }.join
        [ bits[0, (bits.length / 8) * 8] ].pack("B*")
      end
      private_class_method :decode_base32
    end
  end
end
