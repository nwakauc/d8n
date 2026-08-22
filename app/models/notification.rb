class Notification < ApplicationRecord
  belongs_to :brand
  belongs_to :user
  belongs_to :brand_membership
  belongs_to :notification_event

  has_many :notification_deliveries, dependent: :restrict_with_exception

  scope :kept, -> { where(deleted_at: nil) }
  scope :unread, -> { kept.where(read_at: nil) }

  validates :public_id, :notification_type, presence: true
  validates :public_id, uniqueness: true, format: { with: Profile::PUBLIC_ID_FORMAT }
  validates :notification_event_id, uniqueness: true
  validate :membership_matches_recipient
  validate :event_matches_recipient
  validate :payload_is_safe_for_type

  before_validation :ensure_public_id, on: :create

  def mark_read!
    update!(read_at: Time.current) if read_at.nil?
  end

  private

  def ensure_public_id
    self.public_id ||= SecureRandom.uuid
  end

  def membership_matches_recipient
    return if brand_membership.blank?
    return if brand_membership.brand_id == brand_id && brand_membership.user_id == user_id

    errors.add(:brand_membership, "must belong to the notification brand and recipient")
  end

  def event_matches_recipient
    return if notification_event.blank?
    return if notification_event.brand_id == brand_id && notification_event.user_id == user_id &&
      notification_event.brand_membership_id == brand_membership_id

    errors.add(:notification_event, "must belong to the notification brand, membership, and recipient")
  end

  def payload_is_safe_for_type
    Notifications::Types.validate_payload(notification_type:, payload:, brand:).each do |message|
      errors.add(:payload, message)
    end
  end
end
