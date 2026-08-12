class AuthAttempt < ApplicationRecord
  belongs_to :brand, optional: true
  belongs_to :user, optional: true
  belongs_to :identity_identifier, optional: true
  belongs_to :credential, optional: true

  enum :kind, {
    email_password: 0,
    email_otp: 1,
    phone_otp: 2,
    oauth: 3,
    webauthn: 4,
    recovery_code: 5
  }

  enum :result, { succeeded: 0, failed: 1, throttled: 2, locked: 3 }

  validates :identifier, presence: true
end
