module Admin
  module Mfa
    module RecoveryCodes
      COUNT = 8

      module_function

      def generate
        Array.new(COUNT) { SecureRandom.hex(8).upcase.scan(/.{4}/).join("-") }
      end

      def digest(code)
        Identity::HmacDigest.call(
          purpose: "admin-mfa-recovery-code",
          value: normalize(code)
        )
      end

      def consume!(credential:, code:)
        supplied = digest(code)
        matched = nil

        credential.with_lock do
          digests = credential.recovery_code_digests.dup
          matched = digests.find do |candidate|
            candidate.bytesize == supplied.bytesize &&
              ActiveSupport::SecurityUtils.secure_compare(candidate, supplied)
          end
          if matched
            digests.delete_at(digests.index(matched))
            credential.update!(recovery_code_digests: digests)
          end
        end

        matched.present?
      end

      def normalize(code)
        code.to_s.upcase.gsub(/[^A-Z0-9]/, "")
      end
      private_class_method :normalize
    end
  end
end
