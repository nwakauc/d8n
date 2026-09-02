require "test_helper"

module Profiles
  class FieldPolicyTest < ActiveSupport::TestCase
    test "uses explicit DateZA enabled fields as its write and exposure contract" do
      brand = Brand.new(
        slug: "dateza", name: "DateZA",
        profile_requirements: DatezaProfileCatalog::REQUIREMENTS
      )
      policy = FieldPolicy.new(brand:)

      assert_includes policy.writable_profile_fields, "first_name"
      assert_includes policy.writable_profile_fields, "job_title"
      assert_includes policy.writable_profile_fields, "visibility"
      assert_not_includes policy.writable_profile_fields, "pronouns"
      assert policy.public_profile_enabled?("job_title")
      assert_not policy.public_profile_enabled?("birthdate")

      error = assert_raises(FieldPolicy::UnsupportedFields) do
        policy.validate_profile_write!(%w[pronouns unknown body_type])
      end
      assert_equal %w[body_type pronouns], error.fields
    end

    test "preserves the broad legacy field contract when a brand has no enabled list" do
      brand = Brand.new(
        slug: "hookus", name: "HookUs",
        profile_requirements: HookusProfileCatalog::REQUIREMENTS
      )
      policy = FieldPolicy.new(brand:)

      assert_equal Configuration::PROFILE_FIELD_LABELS.keys, policy.enabled_profile_fields
      assert_nothing_raised { policy.validate_profile_write!(%w[pronouns body_type unknown]) }
      # HookUs has no explicit enabled_preference_fields -> broad contract retained.
      assert_equal Configuration::PREFERENCE_FIELD_LABELS.keys, policy.enabled_preference_fields
      assert_nothing_raised { policy.validate_preference_write!(%w[country relationship_intent unknown]) }
    end

    test "governs preference writes by the brand's explicit enabled_preference_fields" do
      brand = Brand.new(
        slug: "dateza", name: "DateZA",
        profile_requirements: DatezaProfileCatalog::REQUIREMENTS
      )
      policy = FieldPolicy.new(brand:)

      assert_equal DatezaProfileCatalog::REQUIRED_PREFERENCE_FIELDS.sort,
        policy.writable_preference_fields.sort
      assert policy.preference_enabled?("min_age")
      assert_not policy.preference_enabled?("country")
      assert_not policy.preference_enabled?("relationship_intent")
      assert_nothing_raised { policy.validate_preference_write!(%w[min_age interested_in max_distance_km]) }

      error = assert_raises(FieldPolicy::UnsupportedFields) do
        policy.validate_preference_write!(%w[min_age country relationship_intent unknown_param])
      end
      assert_equal %w[country relationship_intent], error.fields
    end
  end
end
