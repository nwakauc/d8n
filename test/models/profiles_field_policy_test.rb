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
    end
  end
end
