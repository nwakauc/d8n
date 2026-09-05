module Profiles
  # Brand resolution of the canonical scalar-field catalogue (Profiles::FieldCatalog).
  #
  # FieldCatalog owns field SEMANTICS (type, sensitivity, audience ceiling,
  # validation, storage). This class owns the BRAND POLICY over those fields:
  # which are enabled, which may be written, and which may reach a public
  # audience. It never redefines a field — it only selects and narrows.
  #
  # `visibility` is deliberately NOT a catalogue field: it is a platform
  # operational control, so it keeps its explicit allowlist here.
  class FieldPolicy
    class UnsupportedFields < StandardError
      attr_reader :fields

      def initialize(fields)
        @fields = fields.map(&:to_s).sort.freeze
        super("fields are not enabled for this brand")
      end
    end

    OPERATIONAL_WRITE_FIELDS = %w[visibility].freeze

    attr_reader :enabled_identity_fields, :enabled_profile_fields, :enabled_preference_fields

    def initialize(brand:)
      requirements = brand.profile_completion_requirements
      @enabled_identity_fields = resolve(requirements["enabled_identity_fields"], :identity, default_all: false)
      @enabled_profile_fields = resolve(requirements["enabled_profile_fields"], :profile, default_all: true)
      @enabled_preference_fields = resolve(requirements["enabled_preference_fields"], :preference, default_all: true)
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
      known_submitted = Array(submitted_fields).map(&:to_s) & preference_write_fields
      disabled = known_submitted - writable_preference_fields
      raise UnsupportedFields, disabled if disabled.any?
    end

    def writable_preference_fields
      @writable_preference_fields ||= (enabled_preference_fields & preference_write_fields).freeze
    end

    def profile_enabled?(field)
      enabled_profile_fields.include?(field.to_s)
    end

    def preference_enabled?(field)
      enabled_preference_fields.include?(field.to_s)
    end

    def public_profile_enabled?(field)
      field = field.to_s
      return false unless FieldCatalog.defined?(field)

      definition = FieldCatalog.fetch(field)
      return false if definition.sensitive_identity? || definition.pending_storage?

      profile_enabled?(field) && definition.default_audience == :public
    end

    # ---- serializer resolution -------------------------------------------
    # The single API the profile serializers consume. Serializers select values,
    # not policy: these methods answer "which canonical fields may this audience
    # see for this brand", already failed closed. Catalogue order.

    # Identity + profile fields the OWNER may see.
    def owner_serialized_fields
      @owner_serialized_fields ||= serializable(enabled_identity_fields + enabled_profile_fields)
    end

    # Profile fields a PUBLIC audience (other members) may see — the owner set
    # narrowed to fields whose catalogue audience ceiling is :public.
    def public_serialized_fields
      @public_serialized_fields ||=
        serializable(enabled_profile_fields).select { |field| field.default_audience == :public }
    end

    private

    # Map brand-enabled keys to canonical definitions, dropping anything that
    # must never be serialized regardless of how it was enabled: unknown,
    # sensitive-identity (no approved exposure path yet — later slice), or a
    # field whose storage does not exist. Defense in depth over `resolve`.
    def serializable(keys)
      keys.filter_map do |key|
        next unless FieldCatalog.defined?(key)

        field = FieldCatalog.fetch(key)
        next if field.sensitive_identity? || field.pending_storage?

        field
      end
    end

    # A brand's configured list, filtered to real, enable-able canonical fields
    # in the group — an unknown, sensitive-identity, or not-yet-stored field can
    # never become enabled merely because a brand names it (fail closed).
    def resolve(configured, group, default_all:)
      allowed = enableable_keys(group)
      keys = configured.nil? ? (default_all ? allowed : []) : Array(configured).map(&:to_s)
      keys.select { |key| allowed.include?(key) }.freeze
    end

    def enableable_keys(group)
      FieldCatalog.enableable_keys_for_group(group)
    end

    def preference_write_fields
      @preference_write_fields ||= FieldCatalog.keys_for_group(:preference).freeze
    end

    def known_profile_write_fields
      @known_profile_write_fields ||= (
        FieldCatalog.keys_for_group(:identity) +
          FieldCatalog.keys_for_group(:profile) +
          OPERATIONAL_WRITE_FIELDS
      ).uniq.freeze
    end
  end
end
