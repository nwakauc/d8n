module Profiles
  # Date9ja's v1 profile composition (brand foundation slice). Like
  # Profiles::DatezaProfileCatalog and Profiles::HookusProfileCatalog it composes
  # only generic D8N capabilities (Profiles::CapabilityCatalog) with stable
  # semantics; it edits neither the generic catalogue nor another brand's.
  #
  # SCOPE: this is the NON-SENSITIVE skeleton only. Date9ja's legacy sensitive
  # profile fields — faith/religion, ethnicity, tribe, denomination, preferred
  # tribes, and genotype — are deliberately excluded until the retention/option
  # mapping and privacy architecture decisions in
  # docs/migrations/date9ja-to-d8n/DECISIONS.md are resolved. Do not add them
  # here without that approval.
  #
  # It defines onboarding/completion data, not compatibility weights or matching
  # behaviour. Sensitive values are owner-only unless explicitly widened here.
  class Date9jaProfileCatalog
    # Date9ja is a relationship/marriage-leaning Nigerian product; the curated
    # intents reflect that without copying DateZA's or HookUs's copy.
    RELATIONSHIP_INTENTS = %w[
      long_term_relationship
      marriage
      open_to_dating
      friendship
      still_figuring_it_out
    ].freeze

    ENABLED_PROMPTS = %w[
      green_flag looking_for weekend_plan ideal_first_meet geek_out dealbreaker
      make_me_laugh unwind
    ].freeze

    # Every code here must exist in Profiles::CapabilityCatalog::INTERESTS;
    # unknown codes are silently skipped by enable_interests!(only:).
    INTERESTS = %w[
      foodie cooking coffee restaurants live_music festivals afrobeats amapiano
      hip_hop rnb karaoke travel road_trips beach hiking nature gym running
      football basketball gaming movies reading podcasts art photography fashion
      writing volunteering board_games dancing
    ].freeze

    # Generic, non-sensitive capabilities. `has_children`, `wants_children` and
    # `religion_importance` stay owner-only; nothing here is displayed publicly
    # beyond ordinary lifestyle signals.
    ENABLED_CAPABILITIES = [
      { key: "relationship_intent", cardinality: :single, max_selections: 1, only: RELATIONSHIP_INTENTS },
      { key: "has_children", visibility: :owner_only },
      { key: "wants_children", visibility: :owner_only },
      { key: "meeting_pace", only: %w[ chat_first video_call_first few_days meet_soon go_with_the_flow ] },
      { key: "education_level" },
      { key: "social_style" },
      { key: "communication_style" },
      { key: "planning_style" },
      { key: "diet" },
      { key: "sleep_schedule" },
      { key: "travel_frequency" }
    ].freeze

    REQUIRED_IDENTITY_FIELDS = %w[ first_name last_name ].freeze

    # REQUIRED vs ENABLED
    #
    # A field being *enabled* means the brand collects it. A field being
    # *required* means a profile cannot be complete (and therefore cannot
    # publish) without it. The four fields moved out of the required lists below
    # are still enabled, still collected, and still asked for in onboarding —
    # they are simply not publication gates.
    #
    # WHY THEY MOVED (D-7, D-10, D-11, resolved 2026-09-06). The Pass-1 source
    # census measured what Date9ja actually holds for its ~280 migrating
    # members:
    #
    #   max_distance_km  NULL for ALL 288 source rows (census 240)
    #   meeting_pace     no source column has ever existed (census 202 = `none`)
    #   smoking          NULL for 201 (census 212)
    #   drinking         NULL for 113 (census 213)
    #
    # Keeping them required left exactly three options: block every migrated
    # member from publishing until they answer, invent values they never gave,
    # or relax the requirement. Inventing member data is the one this programme
    # has consistently refused (ADR 0027 photo moderation, ADR 0029 video
    # duration), and blocking everyone empties the brand at cutover. So the
    # requirement moved. Nothing was fabricated and nothing was discarded.
    #
    # This is a Date9ja brand-policy statement, not a platform change: other
    # brands' catalogues are untouched, and the shared FieldCatalog still owns
    # what these fields mean and how they validate.
    REQUIRED_PROFILE_FIELDS = %w[
      display_name birthdate gender country_code city bio
    ].freeze
    OPTIONAL_PROFILE_FIELDS = %w[
      smoking drinking occupation job_title school_or_institution looking_for_text
      height_cm body_type languages fitness
    ].freeze
    # The ENABLED set and its order are the brand's public contract and did not
    # change when smoking/drinking stopped being publication gates; only the
    # REQUIRED list above did.
    ENABLED_PROFILE_FIELDS = %w[
      display_name birthdate gender country_code city bio smoking drinking
      occupation job_title school_or_institution looking_for_text height_cm
      body_type languages fitness
    ].freeze
    REQUIRED_PREFERENCE_FIELDS = %w[ interested_in min_age max_age ].freeze
    # Enabled but not required — see REQUIRED_PROFILE_FIELDS above.
    ENABLED_PREFERENCE_FIELDS = %w[ interested_in min_age max_age max_distance_km ].freeze
    REQUIRED_OPTION_GROUPS = %w[
      relationship_intent has_children wants_children
    ].freeze
    # Installed and offered, but never a publication gate: no legacy source
    # exists, so requiring it would block every migrated member forever.
    OPTIONAL_OPTION_GROUPS = %w[ meeting_pace ].freeze

    # Post-onboarding richness is deliberately separate from publication. Fixed,
    # reusable section keys understood by Profiles::RichCompletion; no executable
    # rules in brand data. Sensitive-field-backed sections are omitted.
    RICH_PROFILE_SECTIONS = %w[
      photos about interests prompts work_education lifestyle
      relationship_intent family_plans languages personality
    ].freeze

    REQUIREMENTS = {
      identity_fields: REQUIRED_IDENTITY_FIELDS,
      enabled_identity_fields: REQUIRED_IDENTITY_FIELDS,
      profile_fields: REQUIRED_PROFILE_FIELDS,
      enabled_profile_fields: ENABLED_PROFILE_FIELDS,
      preference_fields: REQUIRED_PREFERENCE_FIELDS,
      enabled_preference_fields: ENABLED_PREFERENCE_FIELDS,
      collections: %w[ photos location ],
      option_groups: REQUIRED_OPTION_GROUPS,
      rich_profile_sections: RICH_PROFILE_SECTIONS
    }.freeze

    AUTH_METHODS = %w[ email_password phone_password ].freeze

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
          auth_methods: AUTH_METHODS
        )
      end

      brand
    end

    private

    attr_reader :brand

    # The generic installer is intentionally additive for existing brands. Date9ja
    # owns a curated interest subset, so a re-run retires choices removed from its
    # catalogue without deleting historical selections.
    def retire_unconfigured_interest_options!
      group = brand.profile_option_groups.kept.find_by!(key: "interests")
      group.profile_options.kept.where.not(code: INTERESTS).find_each(&:status_retired!)
    end
  end
end
