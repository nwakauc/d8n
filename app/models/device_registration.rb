class DeviceRegistration < ApplicationRecord
  belongs_to :brand
  belongs_to :user
  belongs_to :brand_membership

  has_many :notification_deliveries, dependent: :restrict_with_exception

  enum :platform, { ios: 0, android: 1, web: 2 }

  encrypts :token

  scope :kept, -> { where(deleted_at: nil) }
  scope :deliverable, -> { kept.where(enabled: true, revoked_at: nil) }

  validates :public_id, :token, :token_digest, :last_seen_at, presence: true
  validates :public_id, uniqueness: true, format: { with: Profile::PUBLIC_ID_FORMAT }
  validate :membership_matches_owner

  before_validation :ensure_public_id, on: :create
  before_validation :set_token_digest, if: :will_save_change_to_token?

  def revoke!
    update!(enabled: false, revoked_at: Time.current)
  end

  private

  def ensure_public_id
    self.public_id ||= SecureRandom.uuid
  end

  def set_token_digest
    self.token_digest = Identity::HmacDigest.call(purpose: "push-device-token", value: token)
  end

  def membership_matches_owner
    return if brand_membership.blank?
    return if brand_membership.brand_id == brand_id && brand_membership.user_id == user_id

    errors.add(:brand_membership, "must belong to the device brand and user")
  end
end
