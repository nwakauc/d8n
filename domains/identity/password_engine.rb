module Identity
  class PasswordEngine
    class InvalidCredential < StandardError; end
    class InvalidPassword < StandardError; end

    def self.valid?(password:)
      rodauth.password_meets_requirements?(password.to_s)
    end

    def self.set!(credential:, password:)
      ensure_eligible_credential!(credential)
      raise InvalidPassword unless rodauth.password_meets_requirements?(password.to_s)

      credential.with_lock do
        password_record = CredentialPasswordHash.find_or_initialize_by(credential:)
        password_record.update!(
          password_hash: rodauth.password_hash(password.to_s),
          password_changed_at: Time.current
        )
      end
    end

    def self.matches?(credential:, password:)
      return false unless eligible_credential?(credential)

      D8nPasswordRodauth.valid_login_and_password?(
        account_id: credential.id,
        password: password.to_s
      )
    rescue BCrypt::Errors::InvalidHash
      false
    end

    def self.burn(password:)
      # Rodauth has no public arbitrary-hash verification API. Keep this one
      # version-coupled call isolated and guarded by a compatibility regression.
      rodauth.send(:password_hash_match?, dummy_hash, password.to_s)
      false
    rescue BCrypt::Errors::InvalidHash
      false
    end

    def self.ensure_eligible_credential!(credential)
      raise InvalidCredential unless eligible_credential?(credential)
    end
    private_class_method :ensure_eligible_credential!

    def self.eligible_credential?(credential)
      credential&.persisted? && credential.password? && credential.active? &&
        credential.deleted_at.nil? && credential.identity_identifier.present? &&
        credential.identity_identifier.deleted_at.nil?
    end
    private_class_method :eligible_credential?

    def self.rodauth
      D8nPasswordRodauth.allocate
    end
    private_class_method :rodauth

    def self.dummy_hash
      @dummy_hash ||= rodauth.password_hash(SecureRandom.urlsafe_base64(32))
    end
    private_class_method :dummy_hash
  end
end
