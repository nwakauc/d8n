module Profiles
  # DateZA's v1 profile composition. This deliberately uses only generic
  # D8N capabilities with stable semantics; HookUs-specific intents, vibes, Hook,
  # and Hook Tonight do not belong to DateZA.
  #
  # It defines onboarding/completion data, not compatibility weights or matching
  # behaviour. Sensitive values are owner-only unless explicitly widened here.
  class DatezaProfileCatalog
    RELATIONSHIP_INTENTS = %w[
      long_term_relationship
      marriage
      open_to_dating
      friendship
      still_figuring_it_out
    ].freeze

    ENABLED_PROMPTS = %w[
      green_flag
      ideal_first_meet
      looking_for
      weekend_plan
      geek_out
      dealbreaker
    ].freeze

    INTERESTS = %w[
      foodie cooking coffee live_music festivals afrobeats amapiano hip_hop rnb
      travel road_trips beach hiking nature gym running yoga football rugby cricket
      gaming movies reading podcasts art photography theatre volunteering board_games
    ].freeze

    ENABLED_CAPABILITIES = [
      { key: "relationship_intent", cardinality: :single, max_selections: 1, only: RELATIONSHIP_INTENTS },
      { key: "has_children", visibility: :owner_only },
      { key: "wants_children", visibility: :owner_only },
      { key: "religion_importance", visibility: :owner_only },
      { key: "social_style" },
      { key: "meeting_pace", only: %w[ chat_first video_call_first few_days meet_soon go_with_the_flow ] },
      { key: "education_level" },
      { key: "religion", visibility: :owner_only },
      { key: "diet" },
      { key: "pets" },
      { key: "travel_frequency" },
      { key: "communication_style" },
      { key: "planning_style" }
    ].freeze

    REQUIRED_PROFILE_FIELDS = %w[
      display_name birthdate gender country_code city bio smoking drinking
    ].freeze
    REQUIRED_IDENTITY_FIELDS = %w[ first_name last_name ].freeze
    OPTIONAL_PROFILE_FIELDS = %w[ occupation job_title height_cm languages fitness ].freeze
    REQUIRED_PREFERENCE_FIELDS = %w[ interested_in min_age max_age max_distance_km ].freeze
    REQUIRED_OPTION_GROUPS = %w[
      relationship_intent has_children wants_children religion_importance social_style meeting_pace
    ].freeze

    REQUIREMENTS = {
      identity_fields: REQUIRED_IDENTITY_FIELDS,
      enabled_identity_fields: REQUIRED_IDENTITY_FIELDS,
      profile_fields: REQUIRED_PROFILE_FIELDS,
      enabled_profile_fields: (REQUIRED_PROFILE_FIELDS + OPTIONAL_PROFILE_FIELDS).freeze,
      preference_fields: REQUIRED_PREFERENCE_FIELDS,
      enabled_preference_fields: REQUIRED_PREFERENCE_FIELDS,
      collections: %w[ photos location ],
      option_groups: REQUIRED_OPTION_GROUPS
    }.freeze

    def self.install!(brand:)
      new(brand:).install!
    end

    def initialize(brand:)
      @brand = brand
    end

    def install!
      Brand.transaction do
        ENABLED_CAPABILITIES.each_with_index do |capability, position|
          CapabilityCatalog.enable_option_capability!(brand:, position:, **capability)
        end
        CapabilityCatalog.enable_interests!(
          brand:, position: ENABLED_CAPABILITIES.size, only: INTERESTS, max_selections: 10
        )
        CapabilityCatalog.enable_prompts!(brand:, keys: ENABLED_PROMPTS)
        retire_unconfigured_interest_options!
        brand.update!(
          profile_requirements: REQUIREMENTS,
          auth_methods: %w[ phone_password email_password ]
        )
      end

      brand
    end

    private

    attr_reader :brand

    # The generic installer is intentionally additive for existing brands. DateZA
    # owns a curated interest subset, so a re-run retires choices removed from its
    # catalogue without deleting historical selections.
    def retire_unconfigured_interest_options!
      group = brand.profile_option_groups.kept.find_by!(key: "interests")
      group.profile_options.kept.where.not(code: INTERESTS).find_each(&:status_retired!)
    end
  end
end
