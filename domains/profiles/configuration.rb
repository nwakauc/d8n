module Profiles
  class Configuration
    PROFILE_FIELD_LABELS = {
      "display_name" => "First name",
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

    def self.call(brand:)
      new(brand:).call
    end

    def initialize(brand:)
      @brand = brand
    end

    def call
      requirements = brand.profile_completion_requirements

      {
        profile_fields: fields(PROFILE_FIELD_LABELS, requirements.fetch("profile_fields")),
        preference_fields: fields(PREFERENCE_FIELD_LABELS, requirements.fetch("preference_fields")),
        collections: fields(COLLECTION_LABELS, requirements.fetch("collections")),
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

    def fields(labels, required_keys)
      labels.map do |key, label|
        { key:, label:, required: required_keys.include?(key) }
      end
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
