module Profiles
  # Builds the client-facing profile configuration payload
  # (GET /api/v1/profile/configuration). Scalar-field semantics — labels, input
  # type, cardinality, visibility, and value-source/options — are derived from
  # the canonical Profiles::FieldCatalog; this class owns only the brand
  # composition (which fields, which are required) and the non-scalar sections
  # (collections, option groups, prompts, openers).
  class Configuration
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
        identity_fields: fields(:identity, requirements.fetch("enabled_identity_fields", []),
          requirements.fetch("identity_fields")),
        profile_fields: fields(:profile,
          requirements.fetch("enabled_profile_fields", FieldCatalog.enableable_keys_for_group(:profile)),
          requirements.fetch("profile_fields")),
        preference_fields: fields(:preference,
          requirements.fetch("enabled_preference_fields", FieldCatalog.enableable_keys_for_group(:preference)),
          requirements.fetch("preference_fields")),
        collections: collections(requirements.fetch("collections")),
        option_groups: option_groups(requirements.fetch("option_groups")),
        prompts: prompts,
        openers: openers
      }
    end

    private

    attr_reader :brand

    def prompts
      brand.profile_prompts.kept.status_active.ordered.map do |prompt|
        { key: prompt.key, text: prompt.text, category: prompt.category }
      end
    end

    # Empty for a freeform brand (HookUs) that has no catalog installed; a brand
    # whose opener policy requires curation (DateZA) seeds its own set — see
    # ProfileOpener / BrandContract::OpenerConfiguration#catalog_required.
    def openers
      brand.profile_openers.kept.status_active.ordered.map do |opener|
        { key: opener.key, text: opener.text }
      end
    end

    # Enabled canonical fields in the group, in catalogue (presentation) order.
    def fields(group, enabled_keys, required_keys)
      enabled = Array(enabled_keys).map(&:to_s)

      FieldCatalog.for_group(group).select do |field|
        # A sensitive-identity or not-yet-stored capability is never advertised,
        # even if brand configuration names it (fail closed).
        enabled.include?(field.key) && !field.sensitive_identity? && !field.pending_storage?
      end.map do |field|
        {
          key: field.key,
          label: field.label,
          required: required_keys.include?(field.key),
          cardinality: field.cardinality,
          input_type: field.input_type,
          visibility: field.owner_only_ceiling? ? "owner_only" : "public_profile",
          options: field_options(field)
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

    def field_options(field)
      return Profiles::Languages.catalog if field.value_source == :languages_catalog

      Array(field.validation[:enum]).map { |code| { code:, label: code.humanize } }
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
