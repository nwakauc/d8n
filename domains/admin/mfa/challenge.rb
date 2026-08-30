module Admin
  module Mfa
    class Challenge
      Result = Data.define(:method, :recovery_codes_remaining)

      def self.call(admin_user:, brand:, session:, code:)
        Throttle.check!(admin_user:)
        credential = admin_user.admin_mfa_credentials.kept.active.first
        raise Error, :admin_mfa_enrollment_required if credential.blank?

        method = verify(credential:, code:)
        unless method
          Audit.record!(
            admin_user:, brand:, session:,
            event_type: "admin.mfa_challenge_failed",
            severity: :warning
          )
          raise Error, :admin_mfa_code_invalid
        end

        session.update!(
          admin_mfa_credential: credential,
          admin_mfa_verified_at: Time.current
        )
        Audit.record!(
          admin_user:, brand:, session:,
          event_type: "admin.mfa_challenge_succeeded",
          metadata: { method: }
        )

        Result.new(method:, recovery_codes_remaining: credential.reload.recovery_code_digests.length)
      end

      def self.verify(credential:, code:)
        return "totp" if Totp.valid?(secret: credential.secret, code:)
        return "recovery_code" if RecoveryCodes.consume!(credential:, code:)

        nil
      end
      private_class_method :verify
    end
  end
end
