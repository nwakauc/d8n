class Session < ApplicationRecord
  TOKEN_BYTES = 32
  DEFAULT_TTL = 30.days

  belongs_to :user
  belongs_to :brand

  scope :active, -> { where(revoked_at: nil).where("expires_at > ?", Time.current) }

  validates :token_digest, presence: true, uniqueness: true
  validates :last_used_at, :expires_at, presence: true

  def self.issue!(user:, brand:, device_name: nil, ip_address: nil, user_agent: nil)
    raw_token = SecureRandom.urlsafe_base64(TOKEN_BYTES)
    session = create!(
      user:,
      brand:,
      token_digest: digest_token(raw_token),
      device_name:,
      ip_address:,
      user_agent:,
      last_used_at: Time.current,
      expires_at: DEFAULT_TTL.from_now
    )

    [ raw_token, session ]
  end

  def self.digest_token(token)
    OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, token.to_s)
  end

  def revoked?
    revoked_at.present?
  end

  def expired?
    expires_at <= Time.current
  end
end
