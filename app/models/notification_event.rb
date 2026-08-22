class NotificationEvent < ApplicationRecord
  belongs_to :brand
  belongs_to :user
  belongs_to :brand_membership

  has_one :notification, dependent: :restrict_with_exception

  validates :event_type, :idempotency_key, :occurred_at, presence: true
  validates :idempotency_key, uniqueness: true
  validate :membership_matches_recipient

  after_create_commit :enqueue_processing

  private

  def membership_matches_recipient
    return if brand_membership.blank?
    return if brand_membership.brand_id == brand_id && brand_membership.user_id == user_id

    errors.add(:brand_membership, "must belong to the notification brand and recipient")
  end

  def enqueue_processing
    Notifications::ProcessEventJob.perform_later(id)
  rescue StandardError => error
    Rails.logger.error(
      "[notifications.enqueue_event] event_id=#{id} outcome=failed error=#{error.class.name}"
    )
  end
end
