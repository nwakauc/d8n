module Admin
  module Mfa
    class OfflineReset
      class Unavailable < StandardError; end

      Result = Data.define(:admin_user)

      def self.call(email:)
        login = Identity::LoginIdentifier.call(email)
        identifier = login&.kind == :email &&
          IdentityIdentifier.kept.email.find_by(normalized_value: login.normalized_value)
        admin_user = identifier && AdminUser.kept.find_by(user: identifier.user)
        raise Unavailable, "No active administrative identity is available for that email" if admin_user.blank?

        credential = admin_user.admin_mfa_credentials.kept.first
        raise Unavailable, "No MFA enrollment is available for that administrative identity" if credential.blank?

        ActiveRecord::Base.transaction do
          credential.update!(status: :disabled, deleted_at: Time.current)
          Session.where(admin_mfa_credential: credential).update_all(
            admin_mfa_credential_id: nil,
            admin_mfa_verified_at: nil,
            updated_at: Time.current
          )
          Audit.record!(
            admin_user:,
            brand: nil,
            event_type: "admin.mfa_reset_offline",
            severity: :critical,
            metadata: { recovery: "offline_break_glass" }
          )
        end

        Result.new(admin_user:)
      end
    end
  end
end
