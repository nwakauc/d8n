class Credential < ApplicationRecord
  belongs_to :user
  belongs_to :identity_identifier

  has_many :auth_attempts, dependent: :nullify
  has_many :sessions, dependent: :restrict_with_exception
  has_one :credential_password_hash, dependent: :restrict_with_exception

  enum :kind, {
    password: 0,
    email_otp: 1,
    phone_otp: 2,
    oauth: 3,
    webauthn: 4,
    recovery_code: 5
  }

  enum :status, { active: 0, disabled: 1, revoked: 2 }

  scope :kept, -> { where(deleted_at: nil) }

  validates :identity_identifier_id, uniqueness: {
    scope: [ :user_id, :kind ],
    conditions: -> { kept }
  }
  validate :identity_identifier_belongs_to_user

  private

  def identity_identifier_belongs_to_user
    return if identity_identifier.blank? || user.blank?
    return if identity_identifier.user_id == user_id

    errors.add(:identity_identifier, "must belong to the credential user")
  end
end
