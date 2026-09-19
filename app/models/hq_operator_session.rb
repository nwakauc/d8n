class HqOperatorSession < ApplicationRecord
  TOKEN_BYTES = 32
  DEFAULT_TTL = 7.days

  belongs_to :user
  belongs_to :admin_user
  belongs_to :admin_mfa_credential, optional: true

  scope :active, -> { where(revoked_at: nil).where("expires_at > ?", Time.current) }

  validates :token_digest, presence: true, uniqueness: true
  validates :last_used_at, :expires_at, presence: true

  def self.issue!(user:, admin_user:, device_name: nil, ip_address: nil, user_agent: nil)
    raw_token = SecureRandom.urlsafe_base64(TOKEN_BYTES)
    session = create!(
      user:, admin_user:, token_digest: digest_token(raw_token), device_name:, ip_address:, user_agent:,
      last_used_at: Time.current, expires_at: DEFAULT_TTL.from_now
    )
    [raw_token, session]
  end

  def self.digest_token(token)
    Identity::HmacDigest.call(purpose: "hq-operator-session-token", value: token)
  end

  def admin_mfa_verified_for?(operator)
    admin_mfa_verified_at.present? &&
      admin_mfa_credential&.admin_user_id == operator.id &&
      admin_mfa_credential.deleted_at.nil? && admin_mfa_credential.confirmed?
  end

  def revoked?
    revoked_at.present?
  end

  def expired?
    expires_at <= Time.current
  end
end
