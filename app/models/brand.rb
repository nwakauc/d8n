class Brand < ApplicationRecord
  DEFAULT_PROFILE_REQUIREMENTS = {
    "identity_fields" => [],
    "profile_fields" => %w[ display_name birthdate gender ],
    "preference_fields" => %w[ min_age max_age interested_in ],
    "collections" => %w[ photos ],
    "option_groups" => []
  }.freeze
  PROFILE_CONFIGURATION_KEYS = %w[
    enabled_identity_fields enabled_profile_fields enabled_preference_fields rich_profile_sections
    minimum_lengths conditional_profile_fields conditional_option_groups migration_completion
  ].freeze
  # Requirement keys a brand may relax for a migration-origin profile via
  # `migration_completion`. Each relaxation must be a strict subset of the same
  # top-level requirement, so it can only remove a publication gate.
  MIGRATION_COMPLETION_LIST_KEYS = %w[
    identity_fields profile_fields preference_fields collections option_groups
  ].freeze
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
  has_many :profile_openers, dependent: :restrict_with_exception
  has_many :profile_locations, dependent: :restrict_with_exception
  has_many :find_profile_exposures, dependent: :restrict_with_exception
  has_many :discovery_allocations, dependent: :restrict_with_exception
  has_many :discovery_allocation_candidates, dependent: :restrict_with_exception
  has_many :likes, dependent: :restrict_with_exception
  has_many :profile_passes, dependent: :restrict_with_exception
  has_many :matches, dependent: :restrict_with_exception
  has_many :conversations, dependent: :restrict_with_exception
  has_many :conversation_participants, dependent: :restrict_with_exception
  has_many :profile_blocks, dependent: :restrict_with_exception
  # Migration bindings (ADR 0022) for brand-owned imported records.
  has_many :legacy_references, dependent: :restrict_with_exception
  has_many :migration_profile_readinesses,
    class_name: "Migration::ProfileReadiness",
    dependent: :restrict_with_exception

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
    list_keys = PROFILE_REQUIREMENT_KEYS -
      %w[minimum_lengths conditional_profile_fields conditional_option_groups migration_completion]
    invalid_lists = configured.slice(*list_keys).reject do |_key, value|
      value.is_a?(Array) && value.all? { |item| item.is_a?(String) }
    end
    invalid_structures = !minimum_lengths_shape_valid?(configured["minimum_lengths"]) ||
      !conditional_rules_shape_valid?(configured["conditional_profile_fields"], target_key: "fields") ||
      !conditional_rules_shape_valid?(configured["conditional_option_groups"], target_key: "groups") ||
      !migration_completion_shape_valid?(
        configured["migration_completion"], DEFAULT_PROFILE_REQUIREMENTS.merge(configured)
      )
    if unknown_keys.any? || invalid_lists.any? || invalid_structures
      errors.add(:profile_requirements, "must contain only supported string lists")
      return
    end

    requirements = profile_completion_requirements

    unsupported_identity_fields = requirements.fetch("identity_fields") -
      Profiles::FieldCatalog.completion_requirable_keys(:identity)
    unsupported_profile_fields = requirements.fetch("profile_fields") -
      Profiles::FieldCatalog.completion_requirable_keys(:profile)
    unsupported_preference_fields = requirements.fetch("preference_fields") -
      Profiles::FieldCatalog.completion_requirable_keys(:preference)
    unsupported_collections = requirements.fetch("collections") - Profiles::Completion::SUPPORTED_COLLECTIONS
    unsupported_option_groups = requirements.fetch("option_groups") -
      profile_option_groups.kept.where(key: requirements.fetch("option_groups")).pluck(:key)
    enabled_identity_fields = requirements.fetch("enabled_identity_fields", [])
    enabled_profile_fields = requirements.fetch(
      "enabled_profile_fields", Profiles::FieldCatalog.enableable_keys_for_group(:profile)
    )
    enabled_preference_fields = requirements.fetch(
      "enabled_preference_fields", Profiles::FieldCatalog.enableable_keys_for_group(:preference)
    )
    # A brand may enable only real, non-sensitive, stored canonical fields — a
    # sensitive-identity or `storage: :pending` capability cannot be enabled just
    # by naming it here.
    unsupported_enabled_identity_fields =
      enabled_identity_fields - Profiles::FieldCatalog.enableable_keys_for_group(:identity)
    unsupported_enabled_profile_fields =
      enabled_profile_fields - Profiles::FieldCatalog.enableable_keys_for_group(:profile)
    unsupported_enabled_preference_fields =
      enabled_preference_fields - Profiles::FieldCatalog.enableable_keys_for_group(:preference)
    unsupported_rich_profile_sections = requirements.fetch("rich_profile_sections", []) -
      Profiles::RichCompletion::SECTION_WEIGHTS.keys

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
    if unsupported_rich_profile_sections.any?
      errors.add(:profile_requirements, "contains unsupported rich profile sections")
    end

    validate_minimum_lengths(requirements, enabled_profile_fields)
    validate_conditional_requirements(requirements, enabled_profile_fields)
  end

  def migration_completion_shape_valid?(value, configured)
    return true if value.nil?
    return false unless value.is_a?(Hash)

    value.all? do |key, relaxed|
      case key
      when *MIGRATION_COMPLETION_LIST_KEYS
        relaxed.is_a?(Array) && relaxed.all? { |item| item.is_a?(String) } &&
          (relaxed - Array(configured[key])).empty?
      when "conditional_profile_fields"
        conditional_rules_shape_valid?(relaxed, target_key: "fields")
      when "conditional_option_groups"
        conditional_rules_shape_valid?(relaxed, target_key: "groups")
      else
        false
      end
    end
  end

  def minimum_lengths_shape_valid?(value)
    value.nil? || (value.is_a?(Hash) && value.all? do |field, minimum|
      field.is_a?(String) && minimum.is_a?(Integer) && minimum.positive?
    end)
  end

  def conditional_rules_shape_valid?(value, target_key:)
    value.nil? || (value.is_a?(Array) && value.all? do |rule|
      rule.is_a?(Hash) && rule.keys.map(&:to_s).sort == [ "if", target_key ].sort &&
        rule["if"].is_a?(Hash) && rule["if"].present? &&
        rule["if"].all? { |field, expected| field.is_a?(String) && [ true, false ].include?(expected) } &&
        rule[target_key].is_a?(Array) && rule[target_key].present? &&
        rule[target_key].all? { |item| item.is_a?(String) }
    end)
  end

  def validate_minimum_lengths(requirements, enabled_profile_fields)
    invalid = requirements.fetch("minimum_lengths", {}).any? do |field, minimum|
      next true unless enabled_profile_fields.include?(field) && Profiles::FieldCatalog.defined?(field)

      definition = Profiles::FieldCatalog.fetch(field)
      maximum = definition.validation[:max_length]
      definition.group != :profile || definition.storage[:record] != :profile || maximum.nil? || minimum > maximum
    end
    errors.add(:profile_requirements, "contains unsupported minimum lengths") if invalid
  end

  def validate_conditional_requirements(requirements, enabled_profile_fields)
    condition_fields = requirements.values_at("conditional_profile_fields", "conditional_option_groups")
      .compact.flatten.flat_map { |rule| rule.fetch("if").keys }.uniq
    invalid_conditions = condition_fields.any? do |field|
      next true unless enabled_profile_fields.include?(field) && Profiles::FieldCatalog.defined?(field)

      definition = Profiles::FieldCatalog.fetch(field)
      definition.group != :profile || definition.data_type != :boolean || definition.storage[:record] != :profile
    end

    conditional_fields = requirements.fetch("conditional_profile_fields", []).flat_map { |rule| rule.fetch("fields") }
    invalid_fields = conditional_fields.any? do |field|
      !enabled_profile_fields.include?(field) ||
        !Profiles::FieldCatalog.completion_requirable_keys(:profile).include?(field)
    end

    installed_groups = profile_option_groups.kept.pluck(:key)
    conditional_groups = requirements.fetch("conditional_option_groups", []).flat_map { |rule| rule.fetch("groups") }
    invalid_groups = (conditional_groups - installed_groups).any?

    if invalid_conditions || invalid_fields || invalid_groups
      errors.add(:profile_requirements, "contains unsupported conditional requirements")
    end
  end
end
