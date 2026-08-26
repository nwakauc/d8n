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

  # `suspended` is moderation-only (Admin::SuspendProfile/ReinstateProfile, tied to
  # an AccountEnforcement record). `deactivated` is the distinct self-service,
  # reversible state (Accounts::DeactivateAccount / Identity::AccountReactivation) —
  # never set by admin action, never requires an enforcement record. `left` is the
  # one-way account-deletion tombstone (Accounts::CloseAccount).
  enum :status, { active: 0, suspended: 1, left: 2, deactivated: 3 }

  scope :kept, -> { where(deleted_at: nil) }

  validates :user_id, uniqueness: { scope: :brand_id, conditions: -> { kept } }
end
