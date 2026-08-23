class Brand < ApplicationRecord
  DEFAULT_PROFILE_REQUIREMENTS = {
    "identity_fields" => [],
    "profile_fields" => %w[ display_name birthdate gender ],
    "preference_fields" => %w[ min_age max_age interested_in ],
    "collections" => %w[ photos ],
    "option_groups" => []
  }.freeze
  PROFILE_CONFIGURATION_KEYS = %w[ enabled_identity_fields enabled_profile_fields enabled_preference_fields ].freeze
  PROFILE_REQUIREMENT_KEYS = (DEFAULT_PROFILE_REQUIREMENTS.keys + PROFILE_CONFIGURATION_KEYS).freeze

  has_many :brand_memberships, dependent: :restrict_with_exception
  has_many :brand_domains, dependent: :restrict_with_exception
  has_many :users, through: :brand_memberships
  has_many :admin_assignments, dependent: :restrict_with_exception
  has_many :admin_users, through: :admin_assignments
  has_many :sessions, dependent: :restrict_with_exception
  has_many :otp_challenges, dependent: :restrict_with_exception
  has_many :notification_deliveries, dependent: :restrict_with_exception
  has_many :notification_events, dependent: :restrict_with_exception
  has_many :notifications, dependent: :restrict_with_exception
  has_many :notification_preferences, dependent: :restrict_with_exception
  has_many :device_registrations, dependent: :restrict_with_exception
  has_many :profiles, dependent: :restrict_with_exception
  has_many :profile_preferences, dependent: :restrict_with_exception
  has_many :profile_photos, dependent: :restrict_with_exception
  has_many :profile_option_groups, dependent: :restrict_with_exception
  has_many :profile_options, dependent: :restrict_with_exception
  has_many :profile_option_selections, dependent: :restrict_with_exception
  has_many :profile_prompts, dependent: :restrict_with_exception
  has_many :profile_prompt_answers, dependent: :restrict_with_exception
  has_many :profile_locations, dependent: :restrict_with_exception
  has_many :find_profile_exposures, dependent: :restrict_with_exception
  has_many :likes, dependent: :restrict_with_exception
  has_many :profile_passes, dependent: :restrict_with_exception
  has_many :matches, dependent: :restrict_with_exception
  has_many :conversations, dependent: :restrict_with_exception
  has_many :conversation_participants, dependent: :restrict_with_exception
  has_many :profile_blocks, dependent: :restrict_with_exception

  enum :status, { active: 0, disabled: 1, archived: 2 }

  scope :kept, -> { where(deleted_at: nil) }

  validates :slug, presence: true, uniqueness: { conditions: -> { kept } }
  validates :name, presence: true
  validates :owner_type, presence: true
  validate :auth_methods_are_supported
  validate :profile_requirements_are_supported

  def profile_completion_requirements
    configured = profile_requirements.is_a?(Hash) ? profile_requirements.deep_stringify_keys : {}
    DEFAULT_PROFILE_REQUIREMENTS.merge(configured)
  end

  private

  def auth_methods_are_supported
    unless auth_methods.is_a?(Array) && auth_methods.all? { |method| method.is_a?(String) }
      errors.add(:auth_methods, "must be a list of supported strings")
      return
    end

    errors.add(:auth_methods, "contains duplicates") if auth_methods.uniq.size != auth_methods.size
    unsupported = auth_methods - Identity::AuthPolicy::SUPPORTED_METHODS
    errors.add(:auth_methods, "contains unsupported methods") if unsupported.any?
  end

  def profile_requirements_are_supported
    unless profile_requirements.is_a?(Hash)
      errors.add(:profile_requirements, "must be an object")
      return
    end

    configured = profile_requirements.deep_stringify_keys
    unknown_keys = configured.keys - PROFILE_REQUIREMENT_KEYS
    invalid_lists = configured.slice(*PROFILE_REQUIREMENT_KEYS).reject do |_key, value|
      value.is_a?(Array) && value.all? { |item| item.is_a?(String) }
    end
    if unknown_keys.any? || invalid_lists.any?
      errors.add(:profile_requirements, "must contain only supported string lists")
      return
    end

    requirements = profile_completion_requirements

    unsupported_identity_fields = requirements.fetch("identity_fields") - Profiles::Completion::SUPPORTED_IDENTITY_FIELDS
    unsupported_profile_fields = requirements.fetch("profile_fields") - Profiles::Completion::SUPPORTED_PROFILE_FIELDS
    unsupported_preference_fields = requirements.fetch("preference_fields") - Profiles::Completion::SUPPORTED_PREFERENCE_FIELDS
    unsupported_collections = requirements.fetch("collections") - Profiles::Completion::SUPPORTED_COLLECTIONS
    unsupported_option_groups = requirements.fetch("option_groups") -
      profile_option_groups.kept.where(key: requirements.fetch("option_groups")).pluck(:key)
    enabled_identity_fields = requirements.fetch("enabled_identity_fields", [])
    enabled_profile_fields = requirements.fetch("enabled_profile_fields", Profiles::Configuration::PROFILE_FIELD_LABELS.keys)
    enabled_preference_fields = requirements.fetch(
      "enabled_preference_fields", Profiles::Configuration::PREFERENCE_FIELD_LABELS.keys
    )
    unsupported_enabled_identity_fields = enabled_identity_fields - Profiles::Configuration::IDENTITY_FIELD_LABELS.keys
    unsupported_enabled_profile_fields = enabled_profile_fields - Profiles::Configuration::PROFILE_FIELD_LABELS.keys
    unsupported_enabled_preference_fields = enabled_preference_fields - Profiles::Configuration::PREFERENCE_FIELD_LABELS.keys

    errors.add(:profile_requirements, "contains unsupported identity fields") if unsupported_identity_fields.any?
    errors.add(:profile_requirements, "contains unsupported profile fields") if unsupported_profile_fields.any?
    errors.add(:profile_requirements, "contains unsupported preference fields") if unsupported_preference_fields.any?
    errors.add(:profile_requirements, "contains unsupported collections") if unsupported_collections.any?
    errors.add(:profile_requirements, "contains unsupported option groups") if unsupported_option_groups.any?
    if unsupported_enabled_identity_fields.any? || (requirements.fetch("identity_fields") - enabled_identity_fields).any?
      errors.add(:profile_requirements, "contains unsupported enabled identity fields")
    end
    if unsupported_enabled_profile_fields.any? || (requirements.fetch("profile_fields") - enabled_profile_fields).any?
      errors.add(:profile_requirements, "contains unsupported enabled profile fields")
    end
    if unsupported_enabled_preference_fields.any? ||
        (requirements.fetch("preference_fields") - enabled_preference_fields).any?
      errors.add(:profile_requirements, "contains unsupported enabled preference fields")
    end
  end
end
