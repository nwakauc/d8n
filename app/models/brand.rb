class Brand < ApplicationRecord
  DEFAULT_PROFILE_REQUIREMENTS = {
    "profile_fields" => %w[ display_name birthdate gender ],
    "preference_fields" => %w[ min_age max_age interested_in ],
    "collections" => %w[ photos ]
  }.freeze

  has_many :brand_memberships, dependent: :restrict_with_exception
  has_many :brand_domains, dependent: :restrict_with_exception
  has_many :users, through: :brand_memberships
  has_many :admin_assignments, dependent: :restrict_with_exception
  has_many :admin_users, through: :admin_assignments
  has_many :sessions, dependent: :restrict_with_exception
  has_many :otp_challenges, dependent: :restrict_with_exception
  has_many :notification_deliveries, dependent: :restrict_with_exception
  has_many :profiles, dependent: :restrict_with_exception
  has_many :profile_preferences, dependent: :restrict_with_exception
  has_many :profile_photos, dependent: :restrict_with_exception

  enum :status, { active: 0, disabled: 1, archived: 2 }

  scope :kept, -> { where(deleted_at: nil) }

  validates :slug, presence: true, uniqueness: { conditions: -> { kept } }
  validates :name, presence: true
  validates :owner_type, presence: true
  validate :profile_requirements_are_supported

  def profile_completion_requirements
    DEFAULT_PROFILE_REQUIREMENTS.merge((profile_requirements || {}).deep_stringify_keys)
  end

  private

  def profile_requirements_are_supported
    requirements = profile_completion_requirements

    unsupported_profile_fields = requirements.fetch("profile_fields") - Profiles::Completion::SUPPORTED_PROFILE_FIELDS
    unsupported_preference_fields = requirements.fetch("preference_fields") - Profiles::Completion::SUPPORTED_PREFERENCE_FIELDS
    unsupported_collections = requirements.fetch("collections") - Profiles::Completion::SUPPORTED_COLLECTIONS

    errors.add(:profile_requirements, "contains unsupported profile fields") if unsupported_profile_fields.any?
    errors.add(:profile_requirements, "contains unsupported preference fields") if unsupported_preference_fields.any?
    errors.add(:profile_requirements, "contains unsupported collections") if unsupported_collections.any?
  end
end
