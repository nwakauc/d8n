module Profiles
  class Completion
    # `sections` is an informational breakdown (photos/bio/basics/intent/lifestyle/
    # interests/prompts/verification) for client nudges. It NEVER affects
    # requirements, publication, or visibility — it just describes which optional
    # areas a member has filled in.
    Result = Data.define(:complete?, :percent, :missing, :sections)

    # Which canonical scalar fields a brand may declare as a completion
    # requirement now lives on the canonical field:
    # Profiles::FieldCatalog.completion_requirable_keys(group). Collections are
    # not scalar fields, so their allowlist stays here.
    SUPPORTED_COLLECTIONS = %w[ photos location ].freeze
    COLLECTION_PRESENCE = {
      "photos" => ->(profile) { profile.profile_photos.kept.with_attached_display_image.any?(&:publication_eligible?) },
      "location" => ->(profile) { profile.profile_locations.kept.exists? }
    }.freeze

    # Informational section → option-group keys that count towards it. These are
    # reasonable defaults spanning generic capability keys and brand keys; a brand
    # missing a key simply leaves that section incomplete (harmless).
    INTENT_GROUP_KEYS = %w[ intents relationship_intent ].freeze
    INTERESTS_GROUP_KEYS = %w[ interests vibes ].freeze
    LIFESTYLE_GROUP_KEYS = %w[
      diet cannabis pets pet_preference sleep_schedule social_energy social_style travel_frequency
    ].freeze

    def self.call(profile:)
      new(profile:).call
    end

    def initialize(profile:)
      @profile = profile
    end

    def call
      missing = missing_identity_fields + missing_profile_fields + missing_preference_fields + missing_collections +
        missing_option_groups
      total = identity_fields.size + required_profile_fields.size + preference_fields.size + collections.size +
        required_option_groups.size
      return Result.new(true, 100, [], sections) if total.zero?

      completed = total - missing.size

      Result.new(missing.empty?, ((completed.to_f / total) * 100).round, missing, sections)
    end

    private

    attr_reader :profile

    def sections
      {
        "photos" => {
          complete: profile.profile_photos.kept.with_attached_display_image.any?(&:publication_eligible?)
        },
        "bio" => { complete: profile.bio.present? },
        "basics" => { complete: basics_complete? },
        "intent" => { complete: any_selection?(INTENT_GROUP_KEYS) || preference&.relationship_intent.present? },
        "lifestyle" => { complete: lifestyle_present? },
        "interests" => { complete: any_selection?(INTERESTS_GROUP_KEYS) },
        "prompts" => { complete: profile.prompt_answers.kept.exists? },
        "verification" => { complete: verified? }
      }
    end

    def selected_group_keys
      @selected_group_keys ||= profile.profile_option_selections.kept
        .joins(:profile_option_group).distinct.pluck("profile_option_groups.key")
    end

    def any_selection?(keys)
      (selected_group_keys & keys).any?
    end

    def lifestyle_present?
      any_selection?(LIFESTYLE_GROUP_KEYS) ||
        [ profile.smoking, profile.drinking, profile.fitness ].any?(&:present?)
    end

    def preference
      @preference = ProfilePreference.kept.find_by(profile:) unless defined?(@preference)
      @preference
    end

    def verified?
      IdentityIdentifier.kept.contact.where(user_id: profile.user_id).where.not(verified_at: nil).exists?
    end

    def basics_complete?
      identity_complete = identity_fields.all? { |field| profile.user.public_send(field).present? }
      identity_complete && [ profile.display_name, profile.birthdate, profile.gender ].all?(&:present?)
    end

    def missing_identity_fields
      identity_fields.filter { |field| profile.user.public_send(field).blank? }.map(&:to_sym)
    end

    def missing_profile_fields
      missing = required_profile_fields.filter { |field| !value_present?(profile[field]) }
      minimum_lengths = requirements.fetch("minimum_lengths", {})
      minimum_lengths.each do |field, minimum|
        next unless safe_configured_profile_field?(field) && minimum.is_a?(Integer)

        value = profile[field]
        missing << field if value_present?(value) && value.to_s.length < minimum.to_i
      end
      missing.uniq.map(&:to_sym)
    end

    def required_profile_fields
      (profile_fields + applicable_conditional_profile_fields).uniq
    end

    def applicable_conditional_profile_fields
      Array(requirements["conditional_profile_fields"]).flat_map do |rule|
        condition = rule.fetch("if", {})
        next [] unless configured_condition_matches?(condition)

        Array(rule["fields"]).select { |field| safe_configured_profile_field?(field) }
      end
    end

    def value_present?(value)
      value == false || value.present?
    end

    def missing_preference_fields
      preference = ProfilePreference.kept.find_by(profile:)
      return preference_fields.map { |field| :"preferences.#{field}" } if preference.blank?

      preference_fields.filter_map do |field|
        :"preferences.#{field}" if preference.public_send(field).blank?
      end
    end

    def missing_collections
      collections.reject { |key| COLLECTION_PRESENCE.fetch(key).call(profile) }.map(&:to_sym)
    end

    def missing_option_groups
      selected_keys = profile.profile_option_selections.kept.joins(:profile_option_group)
        .where(profile_option_groups: { key: required_option_groups }).distinct.pluck("profile_option_groups.key")

      required = required_option_groups
      (required - selected_keys).map { |key| :"options.#{key}" }
    end

    def required_option_groups
      (option_groups + conditional_option_groups).uniq
    end

    def conditional_option_groups
      Array(requirements["conditional_option_groups"]).flat_map do |rule|
        condition = rule.fetch("if", {})
        configured_condition_matches?(condition) ? Array(rule["groups"]) : []
      end
    end

    def configured_condition_matches?(condition)
      condition.is_a?(Hash) && condition.present? && condition.all? do |field, expected|
        safe_condition_field?(field) && profile[field] == expected
      end
    end

    def safe_condition_field?(field)
      safe_configured_profile_field?(field) && FieldCatalog.fetch(field).data_type == :boolean
    end

    def safe_configured_profile_field?(field)
      key = field.to_s
      return false unless FieldCatalog.defined?(key)

      definition = FieldCatalog.fetch(key)
      definition.group == :profile && definition.storage[:record] == :profile && profile.has_attribute?(key)
    end

    def requirements
      @requirements ||= profile.brand.profile_completion_requirements
    end

    def profile_fields
      requirements.fetch("profile_fields")
    end

    def identity_fields
      requirements.fetch("identity_fields")
    end

    def preference_fields
      requirements.fetch("preference_fields")
    end

    def collections
      requirements.fetch("collections")
    end

    def option_groups
      requirements.fetch("option_groups")
    end
  end
end
