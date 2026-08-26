module Profiles
  class Configuration
    IDENTITY_FIELD_LABELS = {
      "first_name" => "First name",
      "last_name" => "Last name"
    }.freeze

    PROFILE_FIELD_LABELS = {
      "display_name" => "Display name",
      "bio" => "About me",
      "birthdate" => "Date of birth",
      "gender" => "Gender",
      "pronouns" => "Pronouns",
      "country_code" => "Country",
      "city" => "City",
      "occupation" => "Occupation",
      "job_title" => "Job title",
      "company_name" => "Company",
      "school_or_institution" => "School",
      "looking_for_text" => "What you're looking for",
      "children_count" => "Number of children",
      "height_cm" => "Height",
      "body_type" => "Body type",
      "languages" => "Languages",
      "languages_spoken" => "Languages (legacy)",
      "smoking" => "Smoking",
      "drinking" => "Drinking",
      "fitness" => "Fitness"
    }.freeze

    PREFERENCE_FIELD_LABELS = {
      "min_age" => "Minimum age",
      "max_age" => "Maximum age",
      "interested_in" => "Interested in",
      "max_distance_km" => "Maximum distance",
      "country" => "Preferred country",
      "relationship_intent" => "Relationship intent"
    }.freeze

    COLLECTION_LABELS = { "photos" => "Photos" }.freeze

    FIELD_METADATA = {
      "first_name" => { visibility: "owner_only" },
      "last_name" => { visibility: "owner_only" },
      "bio" => { input_type: "textarea" },
      "birthdate" => { input_type: "date", visibility: "owner_only" },
      "company_name" => { visibility: "owner_only" },
      "children_count" => { input_type: "integer", visibility: "owner_only" },
      "height_cm" => { input_type: "integer" },
      "languages" => { input_type: "language_list", cardinality: "multiple" },
      "languages_spoken" => { input_type: "string_list", cardinality: "multiple" },
      "smoking" => { input_type: "select", options: %w[ never occasionally regularly ] },
      "drinking" => { input_type: "select", options: %w[ never occasionally regularly ] },
      "fitness" => { input_type: "select", options: %w[ never occasionally regularly ] },
      "interested_in" => { input_type: "string_list", cardinality: "multiple" },
      "min_age" => { input_type: "integer" },
      "max_age" => { input_type: "integer" },
      "max_distance_km" => { input_type: "integer" }
    }.freeze

    def self.call(brand:)
      new(brand:).call
    end

    def initialize(brand:)
      @brand = brand
    end

    def call
      requirements = brand.profile_completion_requirements

      {
        identity_fields: fields(
          IDENTITY_FIELD_LABELS.slice(*requirements.fetch("enabled_identity_fields", [])),
          requirements.fetch("identity_fields"),
          default_visibility: "owner_only"
        ),
        profile_fields: fields(
          PROFILE_FIELD_LABELS.slice(*requirements.fetch("enabled_profile_fields", PROFILE_FIELD_LABELS.keys)),
          requirements.fetch("profile_fields")
        ),
        preference_fields: fields(
          PREFERENCE_FIELD_LABELS.slice(*requirements.fetch("enabled_preference_fields", PREFERENCE_FIELD_LABELS.keys)),
          requirements.fetch("preference_fields"),
          default_visibility: "owner_only"
        ),
        collections: collections(requirements.fetch("collections")),
        option_groups: option_groups(requirements.fetch("option_groups")),
        prompts: prompts
      }
    end

    private

    attr_reader :brand

    def prompts
      brand.profile_prompts.kept.status_active.ordered.map do |prompt|
        { key: prompt.key, text: prompt.text, category: prompt.category }
      end
    end

    def fields(labels, required_keys, default_visibility: "public_profile")
      labels.map do |key, label|
        metadata = FIELD_METADATA.fetch(key, {})
        {
          key:,
          label:,
          required: required_keys.include?(key),
          cardinality: metadata.fetch(:cardinality, "single"),
          input_type: metadata.fetch(:input_type, "text"),
          visibility: metadata.fetch(:visibility, default_visibility),
          options: field_options(key, metadata)
        }
      end
    end

    def collections(required_keys)
      COLLECTION_LABELS.map do |key, label|
        {
          key:,
          label:,
          required: required_keys.include?(key),
          minimum_count: 1,
          maximum_count: key == "photos" ? Media::PhotoPolicy.max_count(brand:) : nil
        }.compact
      end
    end

    def field_options(key, metadata)
      return Profiles::Languages.catalog if key == "languages"

      metadata.fetch(:options, []).map { |code| { code:, label: code.humanize } }
    end

    def option_groups(required_keys)
      brand.profile_option_groups.kept.status_active.ordered.includes(:profile_options).map do |group|
        {
          key: group.key,
          label: group.label,
          cardinality: group.cardinality,
          max_selections: group.max_selections,
          required: required_keys.include?(group.key),
          visibility: group.visibility,
          options: group.profile_options.select { |option| option.deleted_at.nil? && option.status_active? }
            .sort_by { |option| [ option.position, option.id ] }
            .map { |option| { code: option.code, label: option.label, category: option.category } }
        }
      end
    end
  end
end
