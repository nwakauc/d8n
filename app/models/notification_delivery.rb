class NotificationDelivery < ApplicationRecord
  belongs_to :brand
  belongs_to :user, optional: true

  enum :channel, { sms: 0, email: 1, push: 2, whatsapp: 3, in_app: 4 }
  enum :status, { pending: 0, sent: 1, failed: 2, skipped: 3 }

  validates :provider, :recipient, presence: true
end
