class BrandMembership < ApplicationRecord
  belongs_to :user
  belongs_to :brand

  has_one :profile, dependent: :restrict_with_exception
  has_many :find_profile_exposures, dependent: :restrict_with_exception
  has_many :discovery_allocations, dependent: :restrict_with_exception
  has_many :notification_events, dependent: :restrict_with_exception
  has_many :notifications, dependent: :restrict_with_exception
  has_many :notification_preferences, dependent: :restrict_with_exception
  has_many :device_registrations, dependent: :restrict_with_exception

  enum :status, { active: 0, suspended: 1, left: 2 }

  scope :kept, -> { where(deleted_at: nil) }

  validates :user_id, uniqueness: { scope: :brand_id, conditions: -> { kept } }
end
