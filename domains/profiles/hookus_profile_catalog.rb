module Profiles
  class HookusProfileCatalog
    GROUPS = [
      {
        key: "intents",
        label: "What are you here for?",
        max_selections: 8,
        options: {
          "hookups" => "Hookups",
          "casual" => "Something casual",
          "dating_vibes" => "Dating and vibes",
          "420_chill" => "420 and chill",
          "nightlife" => "Nightlife",
          "relationship" => "Relationship",
          "travel" => "Travel",
          "just_looking" => "Just looking"
        }
      },
      {
        key: "vibes",
        label: "Vibes",
        max_selections: 15,
        options: {
          "420_friendly" => "420 friendly",
          "drinks" => "Drinks",
          "nightlife" => "Nightlife",
          "raves" => "Raves",
          "music" => "Music",
          "travel" => "Travel",
          "beach" => "Beach",
          "gaming" => "Gaming",
          "fitness" => "Fitness",
          "pets" => "Pets",
          "creative" => "Creative",
          "night_owl" => "Night owl",
          "chill" => "Chill",
          "smoke_free" => "Smoke free",
          "foodie" => "Foodie"
        }
      }
    ].freeze

    # Photos are deliberately NOT required for completion/publication — HookUs
    # is a hookup site, and plenty of people want to stay anonymous rather
    # than share a photo up front. Photo upload itself is unaffected by this:
    # Profiles::Configuration still lists "photos" as an available collection
    # (just required: false), and POST /api/v1/profile/photos doesn't consult
    # completion requirements at all. Anyone who wants to add photos still can.
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
        GROUPS.each_with_index { |definition, position| install_group!(definition, position:) }
        brand.update!(
          profile_requirements: REQUIREMENTS,
          auth_methods: %w[ phone_password email_password ]
        )
      end

      brand
    end

    private

    attr_reader :brand

    def install_group!(definition, position:)
      group = brand.profile_option_groups.kept.find_or_initialize_by(key: definition.fetch(:key))
      group.update!(
        label: definition.fetch(:label),
        cardinality: :multiple,
        max_selections: definition.fetch(:max_selections),
        visibility: :public_profile,
        status: :active,
        position:
      )

      definition.fetch(:options).each_with_index do |(code, label), option_position|
        option = group.profile_options.kept.find_or_initialize_by(code:)
        option.update!(brand:, label:, status: :active, position: option_position)
      end
    end
  end
end
