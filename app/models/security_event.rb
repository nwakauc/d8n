class SecurityEvent < ApplicationRecord
  belongs_to :brand, optional: true
  belongs_to :user, optional: true

  enum :severity, { info: 0, warning: 1, high: 2, critical: 3 }

  validates :event_type, presence: true
end
