require "test_helper"

module Profiles
  # Slice 1 — the canonical scalar-field catalogue is a pure definition layer.
  # These tests assert SEMANTIC ownership and invariants, not a repository grep:
  #   * canonical definitions live here and nowhere else
  #   * the definition objects are immutable (a brand cannot redefine type /
  #     sensitivity / storage / validation)
  #   * the catalogue reproduces today's field set, labels, owner/public split,
  #     and validation rules EXACTLY (so Slices 2–4 can switch consumers over
  #     with zero behaviour change)
  class FieldCatalogTest < ActiveSupport::TestCase
    test "every definition uses only allowed enum values" do
      FieldCatalog.all.each do |field|
        assert_includes FieldCatalog::GROUPS, field.group, field.key
        assert_includes FieldCatalog::DATA_TYPES, field.data_type, field.key
        assert_includes FieldCatalog::SENSITIVITIES, field.sensitivity, field.key
        assert_includes FieldCatalog::AUDIENCES, field.default_audience, field.key
        assert_includes FieldCatalog::STORAGE_RECORDS, field.storage.fetch(:record), field.key
      end
    end

    test "canonical keys are unique and fetch fails closed on unknown keys" do
      assert_equal FieldCatalog.keys.uniq.sort, FieldCatalog.keys.sort
      assert_raises(FieldCatalog::UnknownField) { FieldCatalog.fetch("no_such_field") }
      refute FieldCatalog.defined?("no_such_field")
    end

    test "definition objects are immutable — a brand cannot redefine a canonical field" do
      field = FieldCatalog.fetch("gender")
      assert field.frozen?
      # Data.define instances expose no writers.
      assert_empty field.class.instance_methods.grep(/\w=\z/) - Object.instance_methods
      assert_raises(FrozenError) { field.validation[:max_length] = 999 }
      # Same identity every fetch — one authoritative instance.
      assert_same field, FieldCatalog.fetch("gender")
    end

    # Codex feature-boundary finding 1 — freezing the Field and its top-level
    # validation Hash is not enough; every nested structure reachable through a
    # canonical definition must be immutable too.
    test "canonical field metadata is DEEPLY frozen, not just top-level" do
      smoking = FieldCatalog.fetch("smoking")
      assert smoking.frozen?
      assert smoking.validation.frozen?
      enum = smoking.validation.fetch(:enum)
      assert enum.frozen?, "smoking's enum array must be frozen"
      assert_raises(FrozenError) { enum << "mutated" }
      # The attempted mutation must not have leaked into the catalogue's
      # authoritative instance.
      assert_equal %w[never occasionally regularly], FieldCatalog.fetch("smoking").validation.fetch(:enum)

      languages_spoken = FieldCatalog.fetch("languages_spoken")
      list_limits = languages_spoken.validation.fetch(:list)
      assert list_limits.frozen?, "nested list-limit hash must be frozen"
      assert_raises(FrozenError) { list_limits[:max_entries] = 999 }
      assert_equal 15, FieldCatalog.fetch("languages_spoken").validation.dig(:list, :max_entries)

      storage = FieldCatalog.fetch("display_name").storage
      assert storage.frozen?, "storage metadata must be frozen"
      assert_raises(FrozenError) { storage[:column] = :hijacked }
      assert_equal :display_name, FieldCatalog.fetch("display_name").storage.fetch(:column)
    end

    # Codex feature-boundary finding 2 — `enableable?` must encode
    # `!sensitive_identity? && !pending_storage?` directly, not merely happen to
    # be correct because every current sensitive field is also storage:pending.
    test "enableable? enforces sensitivity directly, independent of storage" do
      # 1 — a normal stored standard field is enableable.
      assert FieldCatalog.enableable?("display_name")
      # 2 — a storage:pending field is excluded (tribe is also sensitive, but
      # this covers the pending_storage? branch).
      refute FieldCatalog.fetch("tribe").sensitive_identity? == false # sanity: tribe IS sensitive
      refute FieldCatalog.enableable?("tribe")

      # 3 — sensitivity ALONE must be sufficient to exclude, independent of
      # tribe/ethnicity's coincidental storage:pending. Inject a synthetic
      # field that is sensitive_identity but has REAL, non-pending storage
      # (the narrow injection mechanism already used elsewhere in this suite —
      # no production fake field is added).
      sensitive_with_real_storage = FieldCatalog::Field.new(
        key: "__sensitive_but_stored_test_field__", group: :profile, label: "Test",
        data_type: :string, storage: { record: :profile, column: :display_name },
        sensitivity: :sensitive_identity
      )
      refute sensitive_with_real_storage.pending_storage?, "fixture must NOT be pending_storage"
      with_field_catalog_extra(sensitive_with_real_storage) do
        refute FieldCatalog.enableable?("__sensitive_but_stored_test_field__"),
          "sensitive_identity alone must exclude enableable?, independent of storage"
      end

      # 4 — enableable_keys_for_group still excludes both real sensitive fields.
      refute_includes FieldCatalog.enableable_keys_for_group(:profile), "tribe"
      refute_includes FieldCatalog.enableable_keys_for_group(:profile), "ethnicity"
    end

    # ---- parity with the sources this catalogue will replace -----------------

    # Frozen snapshot of the labels Profiles::Configuration hard-coded before
    # Slice 2 moved them here. Guards against accidental drift in the refactor
    # and in future edits.
    HISTORICAL_LABELS = {
      "first_name" => "First name", "last_name" => "Last name",
      "display_name" => "Display name", "bio" => "About me", "birthdate" => "Date of birth",
      "gender" => "Gender", "pronouns" => "Pronouns", "country_code" => "Country", "city" => "City",
      "occupation" => "Occupation", "job_title" => "Job title", "company_name" => "Company",
      "school_or_institution" => "School", "looking_for_text" => "What you're looking for",
      "children_count" => "Number of children", "height_cm" => "Height", "body_type" => "Body type",
      "languages" => "Languages", "languages_spoken" => "Languages (legacy)",
      "smoking" => "Smoking", "drinking" => "Drinking", "fitness" => "Fitness",
      "min_age" => "Minimum age", "max_age" => "Maximum age", "interested_in" => "Interested in",
      "max_distance_km" => "Maximum distance", "country" => "Preferred country",
      "relationship_intent" => "Relationship intent"
    }.freeze

    test "canonical keys and labels match the historical Configuration constants" do
      # HISTORICAL_LABELS is the standard (non-sensitive) scalar set. Sensitive-
      # identity capabilities (tribe, ethnicity) are additionally defined but
      # excluded from the enable-able / advertised sets.
      standard_keys = FieldCatalog.keys - FieldCatalog.sensitive_identity_keys
      assert_equal HISTORICAL_LABELS.keys.sort, standard_keys.sort
      HISTORICAL_LABELS.each { |key, label| assert_equal label, FieldCatalog.fetch(key).label, key }
    end

    test "owner/public split matches the historical FieldPolicy split exactly" do
      # The split FieldPolicy hard-coded before Slice 2 derived it from here.
      # Sensitive-identity fields are owner_only by ceiling; exclude them here —
      # they have dedicated fail-closed coverage.
      historical_owner_only = %w[birthdate company_name children_count]
      profile_owner_only = FieldCatalog.for_group(:profile)
        .reject(&:sensitive_identity?).select(&:owner_only_ceiling?).map(&:key)
      assert_equal historical_owner_only.sort, profile_owner_only.sort

      historical_public = %w[
        display_name bio gender pronouns country_code city occupation job_title
        school_or_institution looking_for_text height_cm body_type languages
        languages_spoken smoking drinking fitness
      ]
      profile_public = FieldCatalog.for_group(:profile).reject(&:owner_only_ceiling?).map(&:key)
      assert_equal historical_public.sort, profile_public.sort

      # Identity and preference fields are entirely owner-only today.
      assert_empty FieldCatalog.for_group(:identity).reject(&:owner_only_ceiling?)
      assert_empty FieldCatalog.for_group(:preference).reject(&:owner_only_ceiling?)
    end

    test "declarative validation descriptors match the current model rules" do
      assert_equal({ max_length: 80 }, FieldCatalog.fetch("display_name").validation)
      assert_equal({ max_length: 1_000 }, FieldCatalog.fetch("bio").validation)
      assert_equal({ integer: true, gte: 100, lte: 250 }, FieldCatalog.fetch("height_cm").validation)
      assert_equal({ integer: true, gte: 0, lte: 30 }, FieldCatalog.fetch("children_count").validation)
      assert_equal(%w[never occasionally regularly], FieldCatalog.fetch("smoking").validation.fetch(:enum))
      assert_equal(/\A[A-Z]{2}\z/, FieldCatalog.fetch("country_code").validation.fetch(:format))
      assert_equal({ integer: true, gte: 18, lte: 120 }, FieldCatalog.fetch("min_age").validation)
      assert_equal({ integer: true, gt: 0, lte: 500 }, FieldCatalog.fetch("max_distance_km").validation)
      assert_equal 15, FieldCatalog.fetch("languages_spoken").validation.dig(:list, :max_entries)
      assert_equal 10, FieldCatalog.fetch("interested_in").validation.dig(:list, :max_entries)
    end

    test "input types and cardinality match Profiles::Configuration metadata" do
      assert_equal "textarea", FieldCatalog.fetch("bio").input_type
      assert_equal "date", FieldCatalog.fetch("birthdate").input_type
      assert_equal "select", FieldCatalog.fetch("smoking").input_type
      assert_equal "multiple", FieldCatalog.fetch("languages").cardinality
      assert_equal "multiple", FieldCatalog.fetch("interested_in").cardinality
      assert_equal "single", FieldCatalog.fetch("gender").cardinality
    end

    # ---- audience ceiling ---------------------------------------------------

    test "effective_audience never exceeds the declared ceiling" do
      owner_only = FieldCatalog.fetch("birthdate")
      assert_equal :owner_only, owner_only.effective_audience(:public)
      assert_equal :owner_only, owner_only.effective_audience(nil)

      public_field = FieldCatalog.fetch("occupation")
      assert_equal :public, public_field.effective_audience(nil)
      assert_equal :public, public_field.effective_audience(:public)
      assert_equal :owner_only, public_field.effective_audience(:owner_only)
      # Garbage brand input falls back to the default, never wider.
      assert_equal :public, public_field.effective_audience(:everyone)
    end

    # ---- sensitive-identity capabilities: DEFINED, not enable-able ---------

    test "tribe and ethnicity are defined, sensitive, pending, and never enable-able" do
      assert_equal %w[ethnicity tribe], FieldCatalog.sensitive_identity_keys.sort
      %w[tribe ethnicity].each do |key|
        field = FieldCatalog.fetch(key)
        assert field.sensitive_identity?, key
        assert field.pending_storage?, key
        assert_equal :owner_only, field.default_audience, key
        refute field.completion_requirable?, key
        refute field.onboarding, key
        refute FieldCatalog.enableable?(key), key
        refute_includes FieldCatalog.enableable_keys_for_group(:profile), key
      end
      # No OTHER pending/sensitive fields snuck in.
      assert_equal %w[ethnicity tribe], FieldCatalog.all.select(&:pending_storage?).map(&:key).sort
    end

    test "bespoke_invariant names reference real, still-explicit model validations" do
      profile_rules = Profile.private_instance_methods(false).map(&:to_s)
      preference_rules = ProfilePreference.private_instance_methods(false).map(&:to_s)
      known = (profile_rules + preference_rules).to_set

      FieldCatalog.all.filter_map(&:bespoke_invariant).each do |name|
        assert_includes known, name, "#{name} is named as a bespoke invariant but no model defines it"
      end
    end

    test "storage columns exist on their declared table" do
      { user: User, profile: Profile, profile_preference: ProfilePreference }.each do |record, model|
        FieldCatalog.all.select { |f| f.storage.fetch(:record) == record }.each do |field|
          assert_includes model.column_names, field.storage.fetch(:column).to_s, field.key
        end
      end
    end
  end
end
