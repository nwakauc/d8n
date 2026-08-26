module D8n
  module Platform
    module Capabilities
      module Id
        DEFINITIONS = [
          CapabilityDefinition.new(key: "id.registration", status: :available,
            implementations: %w[Identity::PasswordRegistration]),
          CapabilityDefinition.new(key: "id.authentication.email_password", status: :available,
            implementations: %w[Identity::PasswordLogin Identity::AuthPolicy]),
          CapabilityDefinition.new(key: "id.authentication.phone_password", status: :available,
            implementations: %w[Identity::PasswordLogin Identity::AuthPolicy]),
          CapabilityDefinition.new(key: "id.session.create", status: :available,
            implementations: %w[Identity::PasswordLogin Session]),
          CapabilityDefinition.new(key: "id.session.destroy", status: :available,
            implementations: %w[Identity::SessionRevoker]),
          CapabilityDefinition.new(key: "id.session.current", status: :available,
            implementations: %w[Identity::SessionAuthenticator]),
          CapabilityDefinition.new(key: "id.session.browser_persistence", status: :available,
            implementations: %w[Identity::BrowserSession Identity::SessionAuthenticator],
            dependencies: %w[id.session.create id.session.destroy id.session.current]),
          CapabilityDefinition.new(key: "id.password_recovery", status: :available,
            implementations: %w[Identity::RecoveryRequester Identity::RecoveryVerifier]),
          CapabilityDefinition.new(key: "id.password_reset", status: :available,
            implementations: %w[Identity::PasswordReset]),
          CapabilityDefinition.new(key: "id.contact_change.email", status: :available,
            implementations: %w[Identity::EmailChangeRequester Identity::EmailChangeVerifier]),
          CapabilityDefinition.new(key: "id.membership", status: :available,
            implementations: %w[BrandMembership]),
          CapabilityDefinition.new(key: "id.account.close_brand_membership", status: :available,
            implementations: %w[Accounts::CloseAccount]),
          CapabilityDefinition.new(key: "id.account.password_change", status: :available,
            implementations: %w[Identity::PasswordChange]),
          CapabilityDefinition.new(key: "id.account.deactivate", status: :available,
            implementations: %w[Accounts::DeactivateAccount Identity::AccountReactivation])
        ].freeze

        def self.definitions = DEFINITIONS
      end
    end
  end
end
