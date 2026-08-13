class OtpChallenge < ApplicationRecord
  belongs_to :brand
  belongs_to :identity_identifier, optional: true

  enum :kind, { phone_otp: 0, phone_verification: 1, email_verification: 2 }

  validates :identifier, :code_digest, :expires_at, presence: true

  scope :active, -> { where(consumed_at: nil).where("expires_at > ?", Time.current) }

  def self.digest_code(code)
    Identity::HmacDigest.call(purpose: "otp-challenge", value: code)
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
