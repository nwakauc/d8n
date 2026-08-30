class OtpChallenge < ApplicationRecord
  belongs_to :brand
  belongs_to :identity_identifier, optional: true

  enum :kind, {
    phone_otp: 0,
    phone_verification: 1,
    email_verification: 2,
    password_recovery: 3,
    password_reset: 4,
    email_change: 5,
    phone_change: 6
  }

  # Plaintext one-time code, encrypted at rest. Present only between challenge
  # creation and successful (or permanently abandoned) delivery; the async
  # delivery worker reads it, sends, then clears it to NULL. `code_digest` — not
  # this column — remains the authoritative verifier for the verify step.
  encrypts :delivery_code

  validates :identifier, :code_digest, :expires_at, presence: true

  scope :active, -> { where(consumed_at: nil).where("expires_at > ?", Time.current) }

  def self.digest_code(code)
    Identity::HmacDigest.call(purpose: "otp-challenge", value: code)
  end

  # A code is still worth delivering only while the challenge is unconsumed,
  # unexpired, and its plaintext has not already been sent-and-cleared.
  def deliverable?
    delivery_code.present? && !consumed? && !expired?
  end

  def clear_delivery_code!
    update!(delivery_code: nil)
  end

  def consume!
    update!(consumed_at: Time.current)
  end

  def expired?
    expires_at <= Time.current
  end

  def consumed?
    consumed_at.present?
  end

  def code_matches?(code)
    ActiveSupport::SecurityUtils.secure_compare(code_digest, self.class.digest_code(code))
  end
end
