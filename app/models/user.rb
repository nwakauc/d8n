class User < ApplicationRecord
  has_many :brand_memberships, dependent: :restrict_with_exception
  has_many :brands, through: :brand_memberships
  has_many :identity_identifiers, dependent: :restrict_with_exception
  has_many :credentials, dependent: :restrict_with_exception
  has_many :auth_attempts, dependent: :nullify
  has_many :security_events, dependent: :nullify
  has_many :sessions, dependent: :restrict_with_exception
  has_many :notification_deliveries, dependent: :nullify
  has_many :notification_events, dependent: :restrict_with_exception
  has_many :notifications, dependent: :restrict_with_exception
  has_many :notification_preferences, dependent: :restrict_with_exception
  has_many :device_registrations, dependent: :restrict_with_exception
  has_many :profiles, dependent: :restrict_with_exception
  has_many :profile_preferences, dependent: :restrict_with_exception
  has_many :profile_photos, dependent: :restrict_with_exception
  has_many :profile_option_selections, dependent: :restrict_with_exception
  has_many :profile_locations, dependent: :restrict_with_exception
  has_many :find_profile_exposures, dependent: :restrict_with_exception
  has_many :conversation_participants, dependent: :restrict_with_exception

  enum :status, { active: 0, suspended: 1, closed: 2 }

  scope :kept, -> { where(deleted_at: nil) }

  validates :first_name, :last_name, length: { maximum: 100 }, allow_blank: true

  before_validation :normalize_private_identity_names

  private

  def normalize_private_identity_names
    self.first_name = first_name.to_s.strip.presence
    self.last_name = last_name.to_s.strip.presence
  end
end
