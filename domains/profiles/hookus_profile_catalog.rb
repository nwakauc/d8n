module Profiles
  # HookUs's brand catalogue: the concrete composition of the generic D8N profile
  # capabilities (Profiles::CapabilityCatalog) that HookUs enables, PLUS the few
  # brand-sensitive capabilities that must NOT be global (the HookUs "intents" and
  # "vibes" groups and their casual/420/nightlife voice). A future brand (DateZA,
  # Date9ja) ships its OWN catalogue like this one — composing a different subset,
  # labels, visibility and values — without editing the generic catalogue.
  #
  # Only the original five profile fields + interested_in + the two brand groups
  # remain REQUIRED for completion. Everything enabled below is OPTIONAL: enabling
  # a capability never adds an onboarding requirement, and thin existing profiles
  # stay valid and discoverable (completion is informational, ADR 0017).
  class HookusProfileCatalog
    # Brand-sensitive groups that stay HookUs-specific (not in the generic catalogue).
    BRAND_GROUPS = [
      {
        key: "intents", label: "What are you here for?", cardinality: :multiple,
        max_selections: 8, visibility: :public_profile,
        options: {
          "hookups" => "Hookups", "casual" => "Something casual",
          "dating_vibes" => "Dating and vibes", "420_chill" => "420 and chill",
          "nightlife" => "Nightlife", "relationship" => "Relationship",
          "travel" => "Travel", "just_looking" => "Just looking"
        }
      },
      {
        key: "vibes", label: "Vibes", cardinality: :multiple, max_selections: 15,
        visibility: :public_profile,
        options: {
          "420_friendly" => "420 friendly", "drinks" => "Drinks", "nightlife" => "Nightlife",
          "raves" => "Raves", "music" => "Music", "travel" => "Travel", "beach" => "Beach",
          "gaming" => "Gaming", "fitness" => "Fitness", "pets" => "Pets",
          "creative" => "Creative", "night_owl" => "Night owl", "chill" => "Chill",
          "smoke_free" => "Smoke free", "foodie" => "Foodie"
        }
      }
    ].freeze

    # Generic capabilities HookUs enables, each as { key:, ...overrides }. Order
    # here is presentation order (positions follow the brand groups). Sensitive
    # capabilities carry an explicit visibility so exposure is always deliberate.
    ENABLED_CAPABILITIES = [
      { key: "meeting_pace" },
      { key: "education_level" },
      { key: "diet" },
      { key: "pets" },
      { key: "pet_preference" },
      { key: "sleep_schedule" },
      { key: "social_energy" },
      { key: "social_style" },
      { key: "communication_style" },
      { key: "planning_style" },
      { key: "travel_frequency" },
      { key: "preferred_time_of_day" },
      # Cannabis is a HookUs first-class, publicly-shown capability; the stable
      # "friendly" code is relabelled to the brand's "420 friendly" copy.
      { key: "cannabis", visibility: :public_profile, label: "420 & cannabis",
        option_labels: { "friendly" => "420 friendly" } },
      # Orientation is sensitive: HookUs deliberately opts it into public display.
      { key: "sexual_orientation", visibility: :public_profile },
      # Kept private (owner-only) on HookUs even though offered.
      { key: "religion", visibility: :owner_only },
      { key: "religion_importance", visibility: :owner_only },
      { key: "has_children", visibility: :owner_only },
      { key: "wants_children", visibility: :owner_only },
      # Intimacy preferences: shown only to an active, still-reachable Match.
      { key: "physical_affection", visibility: :matches_only },
      { key: "public_affection", visibility: :matches_only },
      { key: "chemistry_importance", visibility: :matches_only }
    ].freeze

    # HookUs prompt set: playful/personality-forward, not all suggestive.
    ENABLED_PROMPTS = %w[
      perfect_night win_me_over the_vibe find_me ideal_first_meet cannot_stop
      random_love make_me_laugh guilty_pleasure toxic_trait green_flag adventure
    ].freeze

    # Photos are deliberately NOT required for completion/publication — HookUs is a
    # hookup site and many members stay anonymous rather than share a photo up
    # front. Only these original fields + interested_in + the two brand groups are
    # required; every capability enabled above is OPTIONAL.
    REQUIREMENTS = {
      profile_fields: %w[ display_name bio birthdate gender country_code ],
      preference_fields: %w[ interested_in ],
      collections: [].freeze,
      option_groups: %w[ intents vibes ]
    }.freeze

    def self.install!(brand:)
      new(brand:).install!
    end

    def initialize(brand:)
      @brand = brand
    end

    def install!
      Brand.transaction do
        position = install_brand_groups!(start: 0)
        position = install_capabilities!(start: position)
        position = install_interests!(position:)
        install_prompts!
        brand.update!(
          profile_requirements: REQUIREMENTS,
          auth_methods: %w[ phone_password email_password ]
        )
      end

      brand
    end

    private

    attr_reader :brand

    def install_brand_groups!(start:)
      BRAND_GROUPS.each_with_index do |definition, index|
        CapabilityCatalog.install_option_group!(
          brand:, position: start + index,
          key: definition.fetch(:key), label: definition.fetch(:label),
          cardinality: definition.fetch(:cardinality),
          max_selections: definition.fetch(:max_selections),
          visibility: definition.fetch(:visibility),
          options: definition.fetch(:options).map { |code, label| { code:, label: } }
        )
      end
      start + BRAND_GROUPS.size
    end

    def install_capabilities!(start:)
      ENABLED_CAPABILITIES.each_with_index do |capability, index|
        CapabilityCatalog.enable_option_capability!(brand:, position: start + index, **capability)
      end
      start + ENABLED_CAPABILITIES.size
    end

    def install_interests!(position:)
      CapabilityCatalog.enable_interests!(brand:, position:)
      position + 1
    end

    def install_prompts!
      CapabilityCatalog.enable_prompts!(brand:, keys: ENABLED_PROMPTS)
    end
  end
end
