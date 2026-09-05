require "test_helper"

module Profiles
  # Slice 2 — FieldPolicy, Configuration and Brand validation now derive
  # canonical scalar-field semantics from FieldCatalog. These tests assert the
  # derivation and the fail-closed guards; behaviour-parity for real brands is
  # covered by the existing controller/model/contract suites.
  class FieldCatalogDerivationTest < ActiveSupport::TestCase
    test "FieldPolicy resolves enabled sets from FieldCatalog groups" do
      brand = Brand.new(slug: "x", name: "X", profile_requirements: {
        "enabled_profile_fields" => %w[display_name gender],
        "enabled_preference_fields" => %w[min_age max_age],
        "enabled_identity_fields" => %w[first_name]
      })
      policy = FieldPolicy.new(brand:)

      assert_equal %w[display_name gender], policy.enabled_profile_fields
      assert_equal %w[min_age max_age], policy.enabled_preference_fields
      assert_equal %w[first_name], policy.enabled_identity_fields
    end

    test "FieldPolicy defaults to the full catalogue group when a brand has no list" do
      brand = Brand.new(slug: "x", name: "X", profile_requirements: {})
      policy = FieldPolicy.new(brand:)

      assert_equal FieldCatalog.enableable_keys_for_group(:profile), policy.enabled_profile_fields
      assert_equal FieldCatalog.enableable_keys_for_group(:preference), policy.enabled_preference_fields
      assert_equal [], policy.enabled_identity_fields
    end

    test "an unknown field named by a brand cannot become writable or public" do
      brand = Brand.new(slug: "x", name: "X", profile_requirements: {
        "enabled_profile_fields" => %w[display_name totally_made_up]
      })
      policy = FieldPolicy.new(brand:)

      refute_includes policy.enabled_profile_fields, "totally_made_up"
      refute policy.public_profile_enabled?("totally_made_up")
      # Unknown keys are not "known write fields", so they follow ordinary
      # strong-params behaviour rather than raising invalid_profile_fields.
      assert_nothing_raised { policy.validate_profile_write!(%w[totally_made_up]) }
    end

    test "a sensitive_identity or pending-storage field is rejected even if a brand enables it" do
      sensitive = FieldCatalog::Field.new(
        key: "tribe", group: :profile, label: "Tribe", data_type: :string,
        storage: { record: :profile, column: :tribe }, sensitivity: :sensitive_identity,
        default_audience: :owner_only, validation: { max_length: 60 }
      )
      pending = FieldCatalog::Field.new(
        key: "genotype", group: :profile, label: "Genotype", data_type: :string,
        storage: { record: :pending }, sensitivity: :sensitive_identity,
        default_audience: :owner_only, validation: { max_length: 8 }
      )

      with_field_catalog_extra(sensitive, pending) do
        brand = Brand.new(slug: "x", name: "X", profile_requirements: {
          "enabled_profile_fields" => %w[display_name tribe genotype]
        })
        policy = FieldPolicy.new(brand:)

        assert_equal %w[display_name], policy.enabled_profile_fields
        refute policy.public_profile_enabled?("tribe")
        refute policy.public_profile_enabled?("genotype")
        # They ARE known profile write fields now, so a write attempt is a
        # deterministic rejection, never a silent persist.
        error = assert_raises(FieldPolicy::UnsupportedFields) do
          policy.validate_profile_write!(%w[display_name tribe])
        end
        assert_equal %w[tribe], error.fields
      end
    end

    test "Configuration payload is derived from FieldCatalog (labels, input types, visibility)" do
      brand = Brand.create!(slug: "cfgtest", name: "Cfg", profile_requirements: {
        "profile_fields" => %w[display_name birthdate],
        "enabled_profile_fields" => %w[display_name birthdate gender bio smoking],
        "enabled_preference_fields" => %w[min_age],
        "preference_fields" => %w[min_age]
      })
      payload = Configuration.call(brand:)

      profile = payload.fetch(:profile_fields)
      display = profile.find { |f| f[:key] == "display_name" }
      assert_equal "Display name", display[:label]
      assert_equal "text", display[:input_type]
      assert_equal "public_profile", display[:visibility]
      assert display[:required]

      birthdate = profile.find { |f| f[:key] == "birthdate" }
      assert_equal "owner_only", birthdate[:visibility]
      assert_equal "date", birthdate[:input_type]

      smoking = profile.find { |f| f[:key] == "smoking" }
      assert_equal({ code: "never", label: "Never" }, smoking[:options].first)
      assert_equal "select", smoking[:input_type]
      refute smoking[:required]

      assert_equal %w[min_age], payload.fetch(:preference_fields).map { |f| f[:key] }
    end

    test "Brand validation asks FieldCatalog whether an enabled field exists" do
      brand = Brand.new(slug: "x", name: "X", profile_requirements: {
        "enabled_profile_fields" => %w[display_name not_a_field]
      })
      refute brand.valid?
      assert_includes brand.errors[:profile_requirements], "contains unsupported enabled profile fields"

      brand.profile_requirements = { "enabled_profile_fields" => FieldCatalog.enableable_keys_for_group(:profile) }
      brand.valid?
      refute_includes brand.errors[:profile_requirements], "contains unsupported enabled profile fields"
    end
  end
end
