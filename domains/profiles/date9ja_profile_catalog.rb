module Profiles
  # Date9ja's v1 profile composition (brand foundation slice). Like
  # Profiles::DatezaProfileCatalog and Profiles::HookusProfileCatalog it composes
  # only generic D8N capabilities (Profiles::CapabilityCatalog) with stable
  # semantics; it edits neither the generic catalogue nor another brand's.
  #
  # SCOPE: Date9ja onboarding parity fields and owner-only option groups
  # (religion, tribe, genotype, compatibility answers) are enabled here.
  # Denomination, preferred tribes, and culturally specific matching use remain
  # deferred per docs/migrations/date9ja-to-d8n/DECISIONS.md.
  #
  # It defines onboarding/completion data, not compatibility weights or matching
  # behaviour. Sensitive values are owner-only unless explicitly widened here.
  class Date9jaProfileCatalog
    # Date9ja is a relationship/marriage-leaning Nigerian product; the curated
    # intents reflect that without copying DateZA's or HookUs's copy.
    # Date9ja's legacy `relationship_intention` enum has six values
    # (marriage, courtship, serious_relationship, dating, friendship,
    # activity_partner). D8N represents every one of them: `serious_relationship`
    # reuses the exact-synonym `long_term_relationship`; `courtship`, `dating`
    # and `activity_partner` were added to Profiles::CapabilityCatalog for this
    # brand rather than folded onto a near-neighbour.
    RELATIONSHIP_INTENTS = %w[
      long_term_relationship
      marriage
      courtship
      dating
      open_to_dating
      activity_partner
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
      # Every legacy Date9ja preference/lifestyle enum has a D8N home. These are
      # ENABLED and collected but NOT publication gates (see MIGRATION_COMPLETION
      # and REQUIRED_OPTION_GROUPS): a migrated member is never hidden for a
      # missing enrichment value.
      { key: "children_count", visibility: :owner_only },
      { key: "family_involvement_level", visibility: :owner_only },
      { key: "commitment_timeline" },
      { key: "marital_status", visibility: :owner_only },
      # Lossless homes for the legacy free-text arrays. Collected and preserved,
      # never a publication gate.
      { key: "relationship_values", visibility: :owner_only },
      { key: "dealbreakers", visibility: :owner_only },
      { key: "religion", visibility: :owner_only },
      { key: "religion_importance", visibility: :owner_only },
      { key: "tribe", visibility: :owner_only },
      { key: "genotype", visibility: :owner_only },
      # Remaining sensitive Date9ja identity/culture concepts — lossless homes,
      # owner-only, collected and preserved, never a publication gate.
      { key: "ethnicity", visibility: :owner_only },
      { key: "denomination", visibility: :owner_only },
      { key: "intertribal_marriage_openness", visibility: :owner_only },
      { key: "polygamy_openness", visibility: :owner_only },
      { key: "family_involvement", visibility: :owner_only },
      { key: "faith_practice", visibility: :owner_only },
      { key: "money_providing", visibility: :owner_only },
      { key: "settlement", visibility: :owner_only },
      { key: "children", visibility: :owner_only },
      { key: "conflict", visibility: :owner_only },
      { key: "meeting_pace", only: %w[ chat_first video_call_first few_days meet_soon go_with_the_flow ] },
      { key: "education_level" },
      { key: "social_style" },
      { key: "communication_style" },
      { key: "planning_style" },
      { key: "diet" },
      { key: "sleep_schedule" },
      { key: "travel_frequency" }
    ].freeze

    # Date9ja collapses the profile name into a single given name that doubles as
    # the display name (see `display_name` note below). `last_name` stays enabled
    # and editable but is not a publication gate — legacy `full_name` is often a
    # single token and Date9ja never required a surname.
    REQUIRED_IDENTITY_FIELDS = %w[ first_name ].freeze
    ENABLED_IDENTITY_FIELDS = %w[ first_name last_name ].freeze

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
    #
    # `display_name` is NOT required: Date9ja uses the given name as the display
    # name. `Profiles::CurrentProfile` derives `display_name` from `first_name`
    # for a new member, and the readiness importer sets it to the legacy display
    # name when one exists, otherwise `first_name`. It stays enabled so a member
    # can still choose a distinct display name later.
    REQUIRED_PROFILE_FIELDS = %w[
      birthdate gender country_code city bio is_nigerian
    ].freeze
    OPTIONAL_PROFILE_FIELDS = %w[
      smoking drinking occupation job_title school_or_institution looking_for_text
      height_cm body_type languages fitness state_of_origin nationality
      ideal_partner_description willing_to_relocate relocation_preferences
      interest_in_nigerian_culture
    ].freeze
    # The ENABLED set and its order are the brand's public contract and did not
    # change when smoking/drinking stopped being publication gates; only the
    # REQUIRED list above did.
    ENABLED_PROFILE_FIELDS = %w[
      display_name birthdate gender country_code city bio smoking drinking
      occupation job_title school_or_institution looking_for_text height_cm
      body_type languages fitness is_nigerian
      state_of_origin nationality ideal_partner_description willing_to_relocate relocation_preferences
      interest_in_nigerian_culture
    ].freeze
    # Liquidity-first discovery policy: only orientation (`interested_in`) gates
    # publication. `min_age`/`max_age` stay enabled and editable (and are
    # preserved when a legacy source carried them) but are not a publication or
    # discovery requirement — enforcing them excluded the large majority of
    # migrated members and made the marketplace feel empty. See
    # Matching::EligibilityPolicy::LIQUIDITY_FIRST.
    REQUIRED_PREFERENCE_FIELDS = %w[ interested_in ].freeze
    # Enabled but not required — see REQUIRED_PROFILE_FIELDS above.
    # `preferred_country_codes` is the lossless home for legacy
    # `users.preferred_countries` (multi-country residence preference); it is
    # collected and preserved but never a publication or discovery gate.
    ENABLED_PREFERENCE_FIELDS = %w[
      interested_in min_age max_age max_distance_km preferred_country_codes
    ].freeze
    REQUIRED_OPTION_GROUPS = %w[
      relationship_intent has_children wants_children religion family_involvement faith_practice
      money_providing settlement children conflict
    ].freeze
    # Installed and offered, but never a publication gate: no legacy source
    # exists, so requiring it would block every migrated member forever.
    OPTIONAL_OPTION_GROUPS = %w[ meeting_pace ].freeze

    # MIGRATED LEGACY MEMBER vs. NEW MEMBER ONBOARDING
    #
    # AUTHORITATIVE PRODUCT RULE (2026-09-09): a legacy Date9ja member who
    # finished Date9ja onboarding and is not hidden/suspended/banned/deleted is
    # visible on D8N — exactly as they were on Date9ja. Date9ja never gated
    # visibility on a bio, a photo, a resolved city, a cultural answer, a
    # surname, or a verified email/phone; neither does D8N for that member.
    # Being seen (not interacting — see `verification_requirement`) is what drives
    # the member back to finish verification and enrich their profile.
    #
    # So for a migration-origin profile the ONLY publication gates are the
    # reciprocal-matching essentials that every non-deleted source row already
    # carries: an adult birthdate, a decoded gender, an orientation
    # (`interested_in`, set from `looking_for`), and a given name (which also
    # becomes the display name). Everything else — display_name, country, city,
    # bio, is_nigerian, every option group, the surname — stays enabled and
    # prompted, but is not a gate. Nothing is fabricated.
    #
    # A NEW Date9ja registration has no LegacyReference and keeps the full
    # REQUIRED_* contract above — Profiles::Completion applies this relaxation
    # only to migration-origin profiles.
    #
    # Every entry here is a strict subset of the matching REQUIRED_* list: this
    # can only remove a gate, never add one.
    MIGRATION_COMPLETION = {
      "identity_fields" => %w[ first_name ],
      "profile_fields" => %w[ birthdate gender ],
      "preference_fields" => %w[ interested_in ],
      "collections" => [],
      "option_groups" => [],
      "conditional_profile_fields" => [],
      "conditional_option_groups" => []
    }.freeze

    # Post-onboarding richness is deliberately separate from publication. Fixed,
    # reusable section keys understood by Profiles::RichCompletion; no executable
    # rules in brand data. Sensitive-field-backed sections are omitted.
    RICH_PROFILE_SECTIONS = %w[
      photos about interests prompts work_education lifestyle
      relationship_intent family_plans languages personality
    ].freeze

    REQUIREMENTS = {
      identity_fields: REQUIRED_IDENTITY_FIELDS,
      enabled_identity_fields: ENABLED_IDENTITY_FIELDS,
      profile_fields: REQUIRED_PROFILE_FIELDS,
      enabled_profile_fields: ENABLED_PROFILE_FIELDS,
      preference_fields: REQUIRED_PREFERENCE_FIELDS,
      enabled_preference_fields: ENABLED_PREFERENCE_FIELDS,
      # Date9ja asks for country and city as profile fields. It does not use
      # device coordinates, distance filtering, or a required ProfileLocation.
      collections: %w[ photos ],
      option_groups: REQUIRED_OPTION_GROUPS,
      minimum_lengths: { "bio" => 10 },
      conditional_profile_fields: [
        { "if" => { "is_nigerian" => true }, "fields" => [ "state_of_origin" ] },
        { "if" => { "is_nigerian" => false }, "fields" => [ "nationality" ] }
      ],
      conditional_option_groups: [
        { "if" => { "is_nigerian" => true }, "groups" => [ "tribe" ] }
      ],
      migration_completion: MIGRATION_COMPLETION,
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
        configured = brand.profile_requirements.deep_stringify_keys
        fresh_contract = brand.profile_option_groups.kept.none? && !configured.key?("enabled_profile_fields")
        install_requirements = configured.blank? || configured == Brand::DEFAULT_PROFILE_REQUIREMENTS || fresh_contract
        ENABLED_CAPABILITIES.each_with_index do |capability, position|
          CapabilityCatalog.enable_option_capability!(brand:, position:, **capability)
        end
        CapabilityCatalog.enable_interests!(
          brand:, position: ENABLED_CAPABILITIES.size, only: INTERESTS, max_selections: 10
        )
        CapabilityCatalog.enable_prompts!(brand:, keys: ENABLED_PROMPTS)
        retire_unconfigured_interest_options!
        if install_requirements
          brand.update!(profile_requirements: REQUIREMENTS)
        else
          patched = configured
          if patched.fetch("collections", []).include?("location")
            # Older Date9ja installs treated ProfileLocation as a publication
            # requirement. Remove only that obsolete requirement while preserving
            # any operator-managed changes to the rest of the contract.
            patched = patched.merge("collections" => [ "photos" ])
          end
          unless patched.key?("migration_completion")
            # Installs that predate the migrated-member completion relaxation.
            # Intersect with whatever the operator currently requires so the
            # relaxation stays a strict subset of their contract (can only
            # remove a gate, never add one).
            patched = patched.merge("migration_completion" => relaxation_within(patched))
          end
          brand.update!(profile_requirements: patched) unless patched == configured
        end
        brand.update!(auth_methods: AUTH_METHODS) if brand.auth_methods.blank?
      end

      brand
    end

    private

    attr_reader :brand

    def relaxation_within(configured)
      effective = Brand::DEFAULT_PROFILE_REQUIREMENTS.merge(configured)
      MIGRATION_COMPLETION.to_h do |key, value|
        if value.is_a?(Array) && Brand::MIGRATION_COMPLETION_LIST_KEYS.include?(key)
          [ key, value & Array(effective[key]) ]
        else
          [ key, value ]
        end
      end
    end

    # The generic installer is intentionally additive for existing brands. Date9ja
    # owns a curated interest subset, so a re-run retires choices removed from its
    # catalogue without deleting historical selections.
    def retire_unconfigured_interest_options!
      group = brand.profile_option_groups.kept.find_by!(key: "interests")
      group.profile_options.kept.where.not(code: INTERESTS).find_each(&:status_retired!)
    end
  end
end
