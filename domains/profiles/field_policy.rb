module Profiles
  class FieldPolicy
    class UnsupportedFields < StandardError
      attr_reader :fields

      def initialize(fields)
        @fields = fields.map(&:to_s).sort.freeze
        super("fields are not enabled for this brand")
      end
    end

    OPERATIONAL_WRITE_FIELDS = %w[visibility].freeze
    # Every persisted preference scalar a client may set. Unlike profile fields
    # there are no operational-only preference controls.
    PREFERENCE_WRITE_FIELDS = Configuration::PREFERENCE_FIELD_LABELS.keys.freeze
    OWNER_ONLY_PROFILE_FIELDS = %w[birthdate company_name children_count].freeze
    PUBLIC_PROFILE_FIELDS = (
      Configuration::PROFILE_FIELD_LABELS.keys - OWNER_ONLY_PROFILE_FIELDS
    ).freeze

    attr_reader :enabled_identity_fields, :enabled_profile_fields, :enabled_preference_fields

    def initialize(brand:)
      requirements = brand.profile_completion_requirements
      @enabled_identity_fields = requirements.fetch("enabled_identity_fields", []).map(&:to_s).freeze
      @enabled_profile_fields = requirements.fetch(
        "enabled_profile_fields", Configuration::PROFILE_FIELD_LABELS.keys
      ).map(&:to_s).freeze
      @enabled_preference_fields = requirements.fetch(
        "enabled_preference_fields", Configuration::PREFERENCE_FIELD_LABELS.keys
      ).map(&:to_s).freeze
    end

    def validate_profile_write!(submitted_fields)
      known_submitted = Array(submitted_fields).map(&:to_s) & known_profile_write_fields
      disabled = known_submitted - writable_profile_fields
      raise UnsupportedFields, disabled if disabled.any?
    end

    def writable_profile_fields
      @writable_profile_fields ||= (
        enabled_identity_fields + enabled_profile_fields + OPERATIONAL_WRITE_FIELDS
      ).uniq.freeze
    end

    def validate_preference_write!(submitted_fields)
      known_submitted = Array(submitted_fields).map(&:to_s) & PREFERENCE_WRITE_FIELDS
      disabled = known_submitted - writable_preference_fields
      raise UnsupportedFields, disabled if disabled.any?
    end

    def writable_preference_fields
      @writable_preference_fields ||= (enabled_preference_fields & PREFERENCE_WRITE_FIELDS).freeze
    end

    def profile_enabled?(field)
      enabled_profile_fields.include?(field.to_s)
    end

    def preference_enabled?(field)
      enabled_preference_fields.include?(field.to_s)
    end

    def public_profile_enabled?(field)
      profile_enabled?(field) && PUBLIC_PROFILE_FIELDS.include?(field.to_s)
    end

    private

    def known_profile_write_fields
      @known_profile_write_fields ||= (
        Configuration::IDENTITY_FIELD_LABELS.keys +
          Configuration::PROFILE_FIELD_LABELS.keys +
          OPERATIONAL_WRITE_FIELDS
      ).uniq.freeze
    end
  end
end
