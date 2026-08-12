class User < ApplicationRecord
  has_many :brand_memberships, dependent: :restrict_with_exception
  has_many :brands, through: :brand_memberships
  has_many :identity_identifiers, dependent: :restrict_with_exception
  has_many :credentials, dependent: :restrict_with_exception
  has_many :auth_attempts, dependent: :nullify
  has_many :security_events, dependent: :nullify
  has_many :sessions, dependent: :restrict_with_exception
  has_many :notification_deliveries, dependent: :nullify
  has_many :profiles, dependent: :restrict_with_exception

  enum :status, { active: 0, suspended: 1, closed: 2 }

  scope :kept, -> { where(deleted_at: nil) }
end
