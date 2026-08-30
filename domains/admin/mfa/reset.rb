module Admin
  module Mfa
    class Reset
      def self.call(admin_user:, brand:, session:, code:)
        unless session.admin_mfa_verified_for?(admin_user)
          raise Error, :admin_mfa_required
        end

        Throttle.check!(admin_user:)
        credential = admin_user.admin_mfa_credentials.kept.active.first
        raise Error, :admin_mfa_enrollment_required if credential.blank?

        method = verify(credential:, code:)
        unless method
          Audit.record!(
            admin_user:, brand:, session:,
            event_type: "admin.mfa_reset_failed",
            severity: :warning
          )
          raise Error, :admin_mfa_code_invalid
        end

        credential.update!(status: :disabled, deleted_at: Time.current)
        session.update!(admin_mfa_credential: nil, admin_mfa_verified_at: nil)
        Audit.record!(
          admin_user:, brand:, session:,
          event_type: "admin.mfa_reset",
          severity: :warning,
          metadata: { method: }
        )

        true
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
