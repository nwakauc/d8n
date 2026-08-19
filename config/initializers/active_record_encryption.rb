# Active Record Encryption keys, used today only for the OTP `delivery_code`
# ciphertext (see AddDeliveryCodeToOtpChallenges). The plaintext one-time code is
# held in memory during a request; encrypting the column lets an async worker
# decrypt-and-send after commit without the plaintext landing in Solid Queue job
# arguments, logs, or audit metadata.
#
# FAIL-CLOSED in production: keys MUST be supplied via environment (Kamal secrets).
# A missing key raises at boot rather than silently booting with no crypto material.
# Development/test use static, non-secret defaults so the suite and local runs work
# without provisioning key material — these are safe to commit precisely because
# they never protect production data (mirrors the committed dev master key posture).
module D8N
  module Encryption
    DEV_PRIMARY_KEY = "d8n-dev-ar-encryption-primary-key-0000001".freeze
    DEV_DETERMINISTIC_KEY = "d8n-dev-ar-encryption-deterministic-000001".freeze
    DEV_KEY_DERIVATION_SALT = "d8n-dev-ar-encryption-key-derivation-salt-1".freeze

    # In production the value is mandatory (ENV.fetch raises KeyError when unset);
    # elsewhere it falls back to the committed development default.
    def self.key(env_name, dev_default)
      return ENV.fetch(env_name) if Rails.env.production?

      ENV.fetch(env_name, dev_default)
    end
  end
end

ActiveRecord::Encryption.configure(
  primary_key: D8N::Encryption.key("D8N_AR_ENCRYPTION_PRIMARY_KEY", D8N::Encryption::DEV_PRIMARY_KEY),
  deterministic_key: D8N::Encryption.key("D8N_AR_ENCRYPTION_DETERMINISTIC_KEY", D8N::Encryption::DEV_DETERMINISTIC_KEY),
  key_derivation_salt: D8N::Encryption.key("D8N_AR_ENCRYPTION_KEY_DERIVATION_SALT", D8N::Encryption::DEV_KEY_DERIVATION_SALT)
)
