class NotificationDelivery < ApplicationRecord
  belongs_to :brand
  belongs_to :user, optional: true
  belongs_to :notification, optional: true
  belongs_to :device_registration, optional: true

  enum :channel, { sms: 0, email: 1, push: 2, whatsapp: 3, in_app: 4 }
  enum :status, { pending: 0, sent: 1, failed: 2, skipped: 3, processing: 4 }

  validates :provider, :recipient, presence: true
  validate :product_delivery_matches_notification

  after_create_commit :enqueue_product_delivery

  private

  def product_delivery_matches_notification
    return if notification.blank?
    return if notification.brand_id == brand_id && notification.user_id == user_id

    errors.add(:notification, "must belong to the delivery brand and recipient")
  end

  def enqueue_product_delivery
    return unless notification_id.present? && (email? || push?) && pending?

    Notifications::DeliverProductNotificationJob.perform_later(id)
  rescue StandardError => error
    Rails.logger.error(
      "[notifications.enqueue_delivery] delivery_id=#{id} outcome=failed error=#{error.class.name}"
    )
  end
end
