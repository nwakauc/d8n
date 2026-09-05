module Profiles
  # The canonical D8N catalogue of reusable TYPED / SCALAR profile fields — the
  # scalar-field peer of Profiles::CapabilityCatalog (which owns controlled
  # vocabularies / option groups). Together they are the two authoritative
  # definition layers for D8N profile capability.
  #
  # Each entry is a brand-agnostic definition with a STABLE semantic identity:
  # canonical key, group, data type, declarative validation, catalogue/value
  # source, sensitivity classification, audience ceiling, and storage binding.
  #
  # INVARIANTS (enforced by test, and — from Slice 2 on — by the consumers):
  #   * A brand SELECTS fields and chooses policy (enabled? / required? /
  #     onboarding? / a NARROWER audience). A brand can never redefine a field's
  #     data type, sensitivity, validation, value source, or storage.
  #   * `gender` (or any key) means the same thing in every brand. Brand
  #     differences are policy/config/presentation only.
  #   * A field's effective audience is `min(default_audience, brand policy)` —
  #     never wider than the ceiling declared here.
  #   * `storage: :pending` fields have no column yet: they can be defined for the
  #     next migration slice but cannot be enabled or serialized (fail closed),
  #     mirroring CapabilityCatalog's "a planned capability cannot be enabled".
  #
  # SCOPE (Slice 1): every scalar field that D8N already supports today, defined
  # once, reproducing the current labels, types, validation rules, and the
  # current owner/public split EXACTLY. No consumer reads this yet. Sensitive
  # identity fields (tribe, ethnicity, denomination, …) are added in a later
  # slice with `sensitivity: :sensitive_identity` and enabled by no brand.
  #
  # NOT in this catalogue: `visibility` (a platform operational control, not a
  # profile capability — it keeps its explicit allowlist in Profiles::FieldPolicy)
  # and controlled-vocabulary option groups (Profiles::CapabilityCatalog).
  module FieldCatalog
    GROUPS = %i[identity profile preference].freeze
    DATA_TYPES = %i[string text date integer string_list structured_languages].freeze
    # standard        — ordinary dating-presence signal
    # owner_private    — never shown to other members even if a brand tried
    #                    (raw birthdate, legal name, company, children count)
    # sensitive_identity — identity-sensitive; product/privacy decision pending
    #                    (defined for mapping, enabled by no brand) — later slice
    SENSITIVITIES = %i[standard owner_private sensitive_identity].freeze
    AUDIENCES = %i[public owner_only].freeze
    STORAGE_RECORDS = %i[user profile profile_preference pending].freeze

    # Recursively freezes canonical field metadata (validation descriptors,
    # storage/value-source hashes, and any nested arrays/hashes within them) so
    # that no canonical semantic reachable from a Field can be mutated at
    # runtime — not just the top-level Hash/Array itself. Scalars (String,
    # Symbol, Regexp, Integer, nil, true/false, …) are frozen/returned as-is;
    # `freeze` on an already-immutable value type is a harmless no-op. Defined
    # ahead of `Field` because the field definitions below call it eagerly.
    def self.deep_freeze(value)
      case value
      when Hash
        value.each { |k, v| deep_freeze(k); deep_freeze(v) }
        value.freeze
      when Array
        value.each { |item| deep_freeze(item) }
        value.freeze
      else
        value.freeze
      end
    end

    # A canonical field definition. Immutable; the catalogue is the sole author.
    #
    #   validation      — declarative descriptor consumed by the Profile /
    #                     ProfilePreference models from Slice 4 (see KEYS below).
    #                     It intentionally does NOT try to express every domain
    #                     rule; genuine invariants stay explicit — see
    #                     `bespoke_invariant`.
    #   bespoke_invariant — names a domain rule that remains a hand-written model
    #                     validation and is deliberately NOT generated from
    #                     `validation` (e.g. the 18+ age gate). Documentation of
    #                     the boundary, not an instruction.
    #   completion_requirable — may a brand list this field as a completion /
    #                     publication requirement? (replaces
    #                     Profiles::Completion::SUPPORTED_*_FIELDS). Default true;
    #                     a sensitive-identity or not-yet-stored field never is.
    Field = Data.define(
      :key, :group, :label, :data_type, :input_type, :cardinality,
      :sensitivity, :default_audience, :onboarding, :value_source,
      :storage, :validation, :bespoke_invariant, :completion_requirable
    ) do
      def initialize(key:, group:, label:, data_type:, storage:,
        input_type: nil, cardinality: "single", sensitivity: :standard,
        default_audience: :owner_only, onboarding: true, value_source: nil,
        validation: {}, bespoke_invariant: nil, completion_requirable: true)
        super(
          key: key.to_s.freeze, group:, label: label.freeze, data_type:,
          input_type: (input_type || default_input_type(data_type)).to_s.freeze,
          cardinality: cardinality.to_s.freeze, sensitivity:, default_audience:,
          onboarding:, value_source: FieldCatalog.deep_freeze(value_source),
          storage: FieldCatalog.deep_freeze(storage),
          validation: FieldCatalog.deep_freeze(validation),
          bespoke_invariant: bespoke_invariant&.to_s,
          completion_requirable:
        )
      end

      def pending_storage? = storage.fetch(:record) == :pending
      def sensitive_identity? = sensitivity == :sensitive_identity
      # A field D8N will not expose to other members regardless of brand policy.
      def owner_only_ceiling? = default_audience == :owner_only

      def completion_requirable?
        completion_requirable && !sensitive_identity? && !pending_storage?
      end

      # The audience a brand actually gets: never wider than the ceiling.
      def effective_audience(brand_choice)
        return default_audience if brand_choice.nil?
        return :owner_only if owner_only_ceiling?

        AUDIENCES.include?(brand_choice.to_sym) ? brand_choice.to_sym : default_audience
      end

      private

      def default_input_type(type)
        case type
        when :text then "textarea"
        when :date then "date"
        when :integer then "integer"
        when :string_list then "string_list"
        when :structured_languages then "language_list"
        else "text"
        end
      end
    end

    # ---- Identity fields (platform User storage, owner-scoped onboarding) ------
    IDENTITY = [
      Field.new(
        key: "first_name", group: :identity, label: "First name",
        data_type: :string, storage: { record: :user, column: :first_name },
        sensitivity: :owner_private, default_audience: :owner_only,
        validation: { max_length: 100 }
      ),
      Field.new(
        key: "last_name", group: :identity, label: "Last name",
        data_type: :string, storage: { record: :user, column: :last_name },
        sensitivity: :owner_private, default_audience: :owner_only,
        validation: { max_length: 100 }
      )
    ].freeze

    # ---- Profile scalar fields (shared `profiles` table) ----------------------
    PROFILE = [
      Field.new(
        key: "display_name", group: :profile, label: "Display name",
        data_type: :string, storage: { record: :profile, column: :display_name },
        default_audience: :public, validation: { max_length: 80 }
      ),
      Field.new(
        key: "bio", group: :profile, label: "About me",
        data_type: :text, storage: { record: :profile, column: :bio },
        default_audience: :public, validation: { max_length: 1_000 }
      ),
      Field.new(
        key: "birthdate", group: :profile, label: "Date of birth",
        data_type: :date, storage: { record: :profile, column: :birthdate },
        sensitivity: :owner_private, default_audience: :owner_only,
        validation: { date: true },
        # The 18+ gate and public age-derivation stay explicit on Profile.
        bespoke_invariant: "birthdate_meets_minimum_age"
      ),
      Field.new(
        key: "gender", group: :profile, label: "Gender",
        data_type: :string, storage: { record: :profile, column: :gender },
        default_audience: :public, validation: { max_length: 40 }
      ),
      Field.new(
        key: "pronouns", group: :profile, label: "Pronouns",
        data_type: :string, storage: { record: :profile, column: :pronouns },
        default_audience: :public, validation: { max_length: 40 },
        completion_requirable: false
      ),
      Field.new(
        key: "country_code", group: :profile, label: "Country",
        data_type: :string, storage: { record: :profile, column: :country_code },
        default_audience: :public, value_source: :iso_country_code,
        validation: { format: /\A[A-Z]{2}\z/, normalize: :upcase }
      ),
      Field.new(
        key: "city", group: :profile, label: "City",
        data_type: :string, storage: { record: :profile, column: :city },
        default_audience: :public, validation: { max_length: 120 }
      ),
      Field.new(
        key: "occupation", group: :profile, label: "Occupation",
        data_type: :string, storage: { record: :profile, column: :occupation },
        default_audience: :public, validation: { max_length: 120 }
      ),
      Field.new(
        key: "job_title", group: :profile, label: "Job title",
        data_type: :string, storage: { record: :profile, column: :job_title },
        default_audience: :public, validation: { max_length: 120 },
        completion_requirable: false
      ),
      Field.new(
        key: "company_name", group: :profile, label: "Company",
        data_type: :string, storage: { record: :profile, column: :company_name },
        sensitivity: :owner_private, default_audience: :owner_only,
        validation: { max_length: 120 }, completion_requirable: false
      ),
      Field.new(
        key: "school_or_institution", group: :profile, label: "School",
        data_type: :string, storage: { record: :profile, column: :school_or_institution },
        default_audience: :public, validation: { max_length: 160 },
        completion_requirable: false
      ),
      Field.new(
        key: "looking_for_text", group: :profile, label: "What you're looking for",
        data_type: :text, storage: { record: :profile, column: :looking_for_text },
        default_audience: :public, validation: { max_length: 600 },
        completion_requirable: false
      ),
      Field.new(
        key: "children_count", group: :profile, label: "Number of children",
        data_type: :integer, storage: { record: :profile, column: :children_count },
        sensitivity: :owner_private, default_audience: :owner_only,
        validation: { integer: true, gte: 0, lte: 30 }, completion_requirable: false
      ),
      Field.new(
        key: "height_cm", group: :profile, label: "Height",
        data_type: :integer, storage: { record: :profile, column: :height_cm },
        default_audience: :public, validation: { integer: true, gte: 100, lte: 250 }
      ),
      Field.new(
        key: "body_type", group: :profile, label: "Body type",
        data_type: :string, storage: { record: :profile, column: :body_type },
        default_audience: :public, validation: { max_length: 80 }
      ),
      Field.new(
        key: "languages", group: :profile, label: "Languages",
        data_type: :structured_languages, cardinality: "multiple",
        storage: { record: :profile, column: :languages },
        default_audience: :public, value_source: :languages_catalog,
        validation: { structured: :languages },
        bespoke_invariant: "languages_are_valid", completion_requirable: false
      ),
      Field.new(
        key: "languages_spoken", group: :profile, label: "Languages (legacy)",
        data_type: :string_list, cardinality: "multiple",
        storage: { record: :profile, column: :languages_spoken },
        default_audience: :public,
        validation: { list: { max_entries: 15, item_max_length: 40 } },
        bespoke_invariant: "languages_spoken_are_valid"
      ),
      Field.new(
        key: "smoking", group: :profile, label: "Smoking",
        data_type: :string, input_type: "select",
        storage: { record: :profile, column: :smoking },
        default_audience: :public, validation: { enum: %w[never occasionally regularly] }
      ),
      Field.new(
        key: "drinking", group: :profile, label: "Drinking",
        data_type: :string, input_type: "select",
        storage: { record: :profile, column: :drinking },
        default_audience: :public, validation: { enum: %w[never occasionally regularly] }
      ),
      Field.new(
        key: "fitness", group: :profile, label: "Fitness",
        data_type: :string, input_type: "select",
        storage: { record: :profile, column: :fitness },
        default_audience: :public, validation: { enum: %w[never occasionally regularly] }
      ),

      # ---- Identity-sensitive capabilities — DEFINED, not yet stored --------
      # D8N knows these canonical concepts exist; that is ALL it does. They are
      # `storage: :pending` (no column, cannot be enabled), `sensitive_identity`
      # (never writable / public / owner-serialized / completion-requirable), and
      # enabled by NO brand. The stable thing here is the KEY and its meaning —
      # a self-identified cultural/ethnic identity value. Whether it is finally
      # stored as a scalar code or via a controlled-vocabulary option group, its
      # vocabulary, and any brand's collection/exposure/matching policy are all
      # LATER decisions (docs/migrations/date9ja-to-d8n/DECISIONS.md — "Retain
      # tribe", "Retain ethnicity"). `religion` is deliberately NOT here: it
      # already has canonical controlled-vocabulary ownership in
      # Profiles::CapabilityCatalog and is reused, not redefined.
      Field.new(
        key: "tribe", group: :profile, label: "Tribe",
        data_type: :string, storage: { record: :pending },
        sensitivity: :sensitive_identity, default_audience: :owner_only,
        onboarding: false, value_source: :controlled_pending,
        completion_requirable: false
      ),
      Field.new(
        key: "ethnicity", group: :profile, label: "Ethnicity",
        data_type: :string, storage: { record: :pending },
        sensitivity: :sensitive_identity, default_audience: :owner_only,
        onboarding: false, value_source: :controlled_pending,
        completion_requirable: false
      )
    ].freeze

    # ---- Preference scalar fields (shared `profile_preferences` table) --------
    # All owner-only: they steer discovery, they are never shown to other members.
    PREFERENCE = [
      Field.new(
        key: "min_age", group: :preference, label: "Minimum age",
        data_type: :integer, storage: { record: :profile_preference, column: :min_age },
        default_audience: :owner_only, validation: { integer: true, gte: 18, lte: 120 },
        bespoke_invariant: "age_range_is_ordered"
      ),
      Field.new(
        key: "max_age", group: :preference, label: "Maximum age",
        data_type: :integer, storage: { record: :profile_preference, column: :max_age },
        default_audience: :owner_only, validation: { integer: true, gte: 18, lte: 120 },
        bespoke_invariant: "age_range_is_ordered"
      ),
      Field.new(
        key: "interested_in", group: :preference, label: "Interested in",
        data_type: :string_list, cardinality: "multiple",
        storage: { record: :profile_preference, column: :interested_in },
        default_audience: :owner_only,
        validation: { list: { max_entries: 10, item_max_length: 40 } },
        bespoke_invariant: "interested_in_is_array"
      ),
      Field.new(
        key: "max_distance_km", group: :preference, label: "Maximum distance",
        data_type: :integer, storage: { record: :profile_preference, column: :max_distance_km },
        default_audience: :owner_only, validation: { integer: true, gt: 0, lte: 500 }
      ),
      Field.new(
        key: "country", group: :preference, label: "Preferred country",
        data_type: :string, storage: { record: :profile_preference, column: :country },
        default_audience: :owner_only, value_source: :iso_country_code,
        validation: { max_length: 2, normalize: :upcase }
      ),
      Field.new(
        key: "relationship_intent", group: :preference, label: "Relationship intent",
        data_type: :string, storage: { record: :profile_preference, column: :relationship_intent },
        default_audience: :owner_only, validation: { max_length: 80 }
      )
    ].freeze

    ALL = (IDENTITY + PROFILE + PREFERENCE).freeze
    BY_KEY = ALL.index_by(&:key).freeze
    raise "FieldCatalog: duplicate canonical key" if BY_KEY.size != ALL.size

    class UnknownField < StandardError; end

    module_function

    def all = ALL
    def keys = BY_KEY.keys
    def defined?(key) = BY_KEY.key?(key.to_s)

    def fetch(key)
      BY_KEY.fetch(key.to_s) { raise UnknownField, key.to_s }
    end

    # Fields in a group, in catalogue (presentation) order.
    def for_group(group)
      raise ArgumentError, "unknown group: #{group}" unless GROUPS.include?(group.to_sym)

      ALL.select { |field| field.group == group.to_sym }
    end

    def keys_for_group(group) = for_group(group).map(&:key)

    # Keys in a group a brand may actually enable / that may be advertised or
    # defaulted — excludes sensitive-identity and not-yet-stored capabilities.
    # Use this (never `keys_for_group`) anywhere a brand's field set is defaulted
    # or an "enabled" list is validated. `keys_for_group` stays the "known"
    # superset used only to turn a bad write into a deterministic rejection.
    def enableable_keys_for_group(group)
      for_group(group).reject { |field| field.sensitive_identity? || field.pending_storage? }.map(&:key)
    end

    # Keys D8N will never expose to another member, whatever a brand configures.
    def owner_only_keys = ALL.select(&:owner_only_ceiling?).map(&:key)

    # Keys that CAN reach a public audience when a brand enables + permits them.
    def public_capable_keys = ALL.reject(&:owner_only_ceiling?).map(&:key)

    def sensitive_identity_keys = ALL.select(&:sensitive_identity?).map(&:key)

    # enableable = NOT sensitive_identity AND NOT pending_storage. Checked
    # directly against the field, not inferred from today's coincidence that
    # every sensitive_identity field also happens to be storage:pending.
    def enableable?(key)
      field = fetch(key)
      !field.sensitive_identity? && !field.pending_storage?
    end

    # Keys a brand may declare as a completion / publication requirement.
    # Replaces Profiles::Completion::SUPPORTED_*_FIELDS. Collections are not
    # scalar fields and stay owned by Profiles::Completion::SUPPORTED_COLLECTIONS.
    def completion_requirable_keys(group)
      for_group(group).select(&:completion_requirable?).map(&:key)
    end

    # ---- canonical scalar constraints (category A) -----------------------
    # The single authoritative source for a field's reusable constraint VALUE.
    # The Profile / ProfilePreference models call these from explicit
    # `validates` lines — the rule stays visible in the model, the number lives
    # here. Domain/model invariants (age gate, range ordering, tenant scope,
    # structured languages, list shape) stay hand-written in the models.

    # `length: { maximum: … }`
    def max_length(key) = fetch(key).validation.fetch(:max_length)

    # `inclusion: { in: … }`
    def allowed_values(key) = fetch(key).validation.fetch(:enum)

    # `format: { with: … }`
    def format_pattern(key) = fetch(key).validation.fetch(:format)

    # `numericality: { … }` — translates the declarative descriptor to Rails
    # numericality options. Raises if the field has no numeric descriptor.
    def numericality(key)
      rules = fetch(key).validation
      raise ArgumentError, "#{key} has no numeric constraint" unless rules[:integer]

      options = { only_integer: true }
      options[:greater_than_or_equal_to] = rules[:gte] if rules.key?(:gte)
      options[:greater_than] = rules[:gt] if rules.key?(:gt)
      options[:less_than_or_equal_to] = rules[:lte] if rules.key?(:lte)
      options
    end

    # `{ max_entries:, item_max_length: }` for the hand-written list validators.
    def list_limits(key) = fetch(key).validation.fetch(:list)
  end
end
