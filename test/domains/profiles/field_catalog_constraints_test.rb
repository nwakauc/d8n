require "test_helper"

module Profiles
  # Slice 4 — FieldCatalog is now authoritative for (A) canonical scalar
  # constraint VALUES and (B) which fields may be a completion requirement.
  # These tests pin both to the historical behaviour they replaced.
  class FieldCatalogConstraintsTest < ActiveSupport::TestCase
    # Frozen snapshot of Profiles::Completion::SUPPORTED_*_FIELDS before Slice 4.
    HISTORICAL_COMPLETION_REQUIRABLE = {
      identity: %w[first_name last_name],
      profile: %w[
        display_name bio birthdate gender country_code city occupation height_cm
        body_type languages_spoken smoking drinking fitness
      ],
      preference: %w[min_age max_age interested_in max_distance_km country relationship_intent]
    }.freeze

    test "completion_requirable_keys match the historical Completion SUPPORTED_* sets" do
      HISTORICAL_COMPLETION_REQUIRABLE.each do |group, expected|
        assert_equal expected.sort, FieldCatalog.completion_requirable_keys(group).sort, group
      end
    end

    test "a sensitive-identity or pending field is never completion_requirable" do
      sensitive = FieldCatalog::Field.new(
        key: "tribe", group: :profile, label: "Tribe", data_type: :string,
        storage: { record: :profile, column: :bio }, sensitivity: :sensitive_identity,
        completion_requirable: true, validation: { max_length: 60 }
      )
      pending = FieldCatalog::Field.new(
        key: "genotype", group: :profile, label: "Genotype", data_type: :string,
        storage: { record: :pending }, completion_requirable: true, validation: { max_length: 8 }
      )
      refute sensitive.completion_requirable?
      refute pending.completion_requirable?
    end

    test "canonical constraint accessors return the exact historical model rules" do
      assert_equal 80, FieldCatalog.max_length("display_name")
      assert_equal 1_000, FieldCatalog.max_length("bio")
      assert_equal 600, FieldCatalog.max_length("looking_for_text")
      assert_equal 2, FieldCatalog.max_length("country")
      assert_equal(/\A[A-Z]{2}\z/, FieldCatalog.format_pattern("country_code"))
      assert_equal %w[never occasionally regularly], FieldCatalog.allowed_values("smoking")

      assert_equal(
        { only_integer: true, greater_than_or_equal_to: 100, less_than_or_equal_to: 250 },
        FieldCatalog.numericality("height_cm")
      )
      assert_equal(
        { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 30 },
        FieldCatalog.numericality("children_count")
      )
      assert_equal(
        { only_integer: true, greater_than: 0, less_than_or_equal_to: 500 },
        FieldCatalog.numericality("max_distance_km")
      )
      assert_equal({ max_entries: 15, item_max_length: 40 }, FieldCatalog.list_limits("languages_spoken"))
      assert_equal({ max_entries: 10, item_max_length: 40 }, FieldCatalog.list_limits("interested_in"))
    end

    test "shared ProfilePreference domain constants agree with the catalogue" do
      assert_equal FieldCatalog.numericality("min_age")[:greater_than_or_equal_to], ProfilePreference::MINIMUM_AGE
      assert_equal FieldCatalog.numericality("max_age")[:less_than_or_equal_to], ProfilePreference::MAXIMUM_AGE
      assert_equal FieldCatalog.numericality("max_distance_km")[:less_than_or_equal_to], ProfilePreference::MAX_DISTANCE_KM
      assert_equal FieldCatalog.numericality("min_age")[:greater_than_or_equal_to], Profile::MINIMUM_AGE
    end

    test "numericality raises for a non-numeric field" do
      assert_raises(ArgumentError) { FieldCatalog.numericality("display_name") }
    end
  end
end
