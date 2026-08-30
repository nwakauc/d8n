module Admin
  module Mfa
    class Enrollment
      StartResult = Data.define(:secret, :provisioning_uri)
      ConfirmResult = Data.define(:recovery_codes)

      def self.start(admin_user:, brand:, session:)
        active = admin_user.admin_mfa_credentials.kept.active.first
        raise Error, :admin_mfa_already_enrolled if active.present?

        secret = Totp.generate_secret
        credential = admin_user.admin_mfa_credentials.kept.pending.first_or_initialize
        credential.assign_attributes(secret:, recovery_code_digests: [], confirmed_at: nil)
        credential.save!

        Audit.record!(
          admin_user:, brand:, session:,
          event_type: "admin.mfa_enrollment_started"
        )

        StartResult.new(
          secret:,
          provisioning_uri: Totp.provisioning_uri(secret:, account: account_label(admin_user))
        )
      end

      def self.confirm(admin_user:, brand:, session:, code:)
        Throttle.check!(admin_user:)
        credential = admin_user.admin_mfa_credentials.kept.pending.first
        raise Error, :admin_mfa_enrollment_missing if credential.blank?

        unless Totp.valid?(secret: credential.secret, code:)
          Audit.record!(
            admin_user:, brand:, session:,
            event_type: "admin.mfa_enrollment_failed",
            severity: :warning
          )
          raise Error, :admin_mfa_code_invalid
        end

        recovery_codes = RecoveryCodes.generate
        credential.update!(
          status: :active,
          confirmed_at: Time.current,
          recovery_code_digests: recovery_codes.map { |recovery_code| RecoveryCodes.digest(recovery_code) }
        )
        verify_session!(session:, credential:)
        Audit.record!(
          admin_user:, brand:, session:,
          event_type: "admin.mfa_enrollment_confirmed"
        )

        ConfirmResult.new(recovery_codes:)
      end

      def self.account_label(admin_user)
        admin_user.user.identity_identifiers.kept.email.order(:id).pick(:normalized_value) ||
          "admin-#{admin_user.id}"
      end
      private_class_method :account_label

      def self.verify_session!(session:, credential:)
        session.update!(
          admin_mfa_credential: credential,
          admin_mfa_verified_at: Time.current
        )
      end
      private_class_method :verify_session!
    end
  end
end
