class CredentialPasswordHash < ApplicationRecord
  self.primary_key = :credential_id

  belongs_to :credential

  validates :password_hash, presence: true
  validates :credential_kind, inclusion: { in: [ Credential.kinds.fetch("password") ] }
  validate :credential_uses_password_strategy

  private

  def credential_uses_password_strategy
    return if credential&.password?

    errors.add(:credential, "must use the password strategy")
  end
end
