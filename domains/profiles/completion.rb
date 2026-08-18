module Profiles
  class Completion
    # `sections` is an informational breakdown (photos/bio/basics/intent/lifestyle/
    # interests/prompts/verification) for client nudges. It NEVER affects
    # requirements, publication, or visibility — it just describes which optional
    # areas a member has filled in.
    Result = Data.define(:complete?, :percent, :missing, :sections)

    SUPPORTED_PROFILE_FIELDS = %w[
      display_name bio birthdate gender country_code city occupation height_cm body_type
      languages_spoken smoking drinking fitness
    ].freeze
    SUPPORTED_PREFERENCE_FIELDS = %w[ min_age max_age interested_in max_distance_km country relationship_intent ].freeze
    SUPPORTED_COLLECTIONS = %w[ photos ].freeze

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
      missing = missing_profile_fields + missing_preference_fields + missing_collections + missing_option_groups
      total = profile_fields.size + preference_fields.size + collections.size + option_groups.size
      return Result.new(true, 100, [], sections) if total.zero?

      completed = total - missing.size

      Result.new(missing.empty?, ((completed.to_f / total) * 100).round, missing, sections)
    end

    private

    attr_reader :profile

    def sections
      {
        "photos" => { complete: profile.profile_photos.kept.exists? },
        "bio" => { complete: profile.bio.present? },
        "basics" => { complete: [ profile.display_name, profile.birthdate, profile.gender ].all?(&:present?) },
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
      IdentityIdentifier.kept.where(user_id: profile.user_id).where.not(verified_at: nil).exists?
    end

    def missing_profile_fields
      profile_fields.filter { |field| profile.public_send(field).blank? }.map(&:to_sym)
    end

    def missing_preference_fields
      preference = ProfilePreference.kept.find_by(profile:)
      return preference_fields.map { |field| :"preferences.#{field}" } if preference.blank?

      preference_fields.filter_map do |field|
        :"preferences.#{field}" if preference.public_send(field).blank?
      end
    end

    def missing_collections
      return [] if profile.profile_photos.kept.exists?

      collections.map(&:to_sym)
    end

    def missing_option_groups
      selected_keys = profile.profile_option_selections.kept.joins(:profile_option_group)
        .where(profile_option_groups: { key: option_groups }).distinct.pluck("profile_option_groups.key")

      (option_groups - selected_keys).map { |key| :"options.#{key}" }
    end

    def requirements
      @requirements ||= profile.brand.profile_completion_requirements
    end

    def profile_fields
      requirements.fetch("profile_fields")
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
