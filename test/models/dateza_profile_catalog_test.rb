require "test_helper"

module Profiles
  class DatezaProfileCatalogTest < ActiveSupport::TestCase
    test "composes the DateZA v1 profile contract idempotently" do
      brand = Brand.create!(slug: "dateza", name: "DateZA")

      assert_difference -> { ProfileOptionGroup.count }, DatezaProfileCatalog::ENABLED_CAPABILITIES.size + 1 do
        assert_difference -> { ProfilePrompt.count }, DatezaProfileCatalog::ENABLED_PROMPTS.size do
          DatezaProfileCatalog.install!(brand:)
        end
      end

      assert_no_difference [
        -> { ProfileOptionGroup.count }, -> { ProfileOption.count }, -> { ProfilePrompt.count }
      ] do
        DatezaProfileCatalog.install!(brand:)
      end

      requirements = brand.reload.profile_completion_requirements
      assert_equal DatezaProfileCatalog::REQUIRED_IDENTITY_FIELDS, requirements.fetch("identity_fields")
      assert_equal DatezaProfileCatalog::REQUIRED_IDENTITY_FIELDS, requirements.fetch("enabled_identity_fields")
      assert_equal DatezaProfileCatalog::REQUIRED_OPTION_GROUPS, requirements.fetch("option_groups")
      assert_equal DatezaProfileCatalog::REQUIRED_PROFILE_FIELDS, requirements.fetch("profile_fields")
      assert_equal DatezaProfileCatalog::REQUIRED_PREFERENCE_FIELDS, requirements.fetch("preference_fields")
      assert_equal DatezaProfileCatalog::REQUIRED_PROFILE_FIELDS + DatezaProfileCatalog::OPTIONAL_PROFILE_FIELDS,
        requirements.fetch("enabled_profile_fields")
      assert_equal %w[ photos ], requirements.fetch("collections")
      assert_equal %w[ phone_password email_password ], brand.auth_methods
    end

    test "uses generic relationship and interest capabilities without HookUs semantics" do
      brand = Brand.create!(slug: "dateza", name: "DateZA")
      DatezaProfileCatalog.install!(brand:)

      groups = brand.profile_option_groups.kept.index_by(&:key)
      assert_equal(DatezaProfileCatalog::ENABLED_CAPABILITIES.pluck(:key).push("interests").sort, groups.keys.sort)
      assert_equal DatezaProfileCatalog::RELATIONSHIP_INTENTS.sort,
        groups.fetch("relationship_intent").profile_options.kept.pluck(:code).sort
      assert groups.fetch("relationship_intent").visibility_public_profile?
      assert groups.fetch("interests").visibility_public_profile?
      assert groups.fetch("has_children").visibility_owner_only?
      assert groups.fetch("religion_importance").visibility_owner_only?
      assert groups.fetch("relationship_intent").cardinality_single?
      assert_equal DatezaProfileCatalog::INTERESTS.sort,
        groups.fetch("interests").profile_options.kept.status_active.pluck(:code).sort
      assert_not groups.key?("intents")
      assert_not groups.key?("vibes")
    end

    test "exposes only DateZA enabled scalar fields with render metadata" do
      brand = Brand.create!(slug: "dateza", name: "DateZA")
      DatezaProfileCatalog.install!(brand:)

      configuration = Configuration.call(brand:)
      identity_fields = configuration.fetch(:identity_fields).index_by { |field| field.fetch(:key) }
      fields = configuration.fetch(:profile_fields).index_by { |field| field.fetch(:key) }
      preferences = configuration.fetch(:preference_fields).index_by { |field| field.fetch(:key) }

      assert_equal %w[ first_name last_name ], identity_fields.keys
      assert identity_fields.fetch("first_name").fetch(:required)
      assert identity_fields.fetch("last_name").fetch(:required)
      assert_equal "owner_only", identity_fields.fetch("last_name").fetch(:visibility)
      assert_equal "Display name", fields.fetch("display_name").fetch(:label)
      assert_equal(
        (DatezaProfileCatalog::REQUIRED_PROFILE_FIELDS + DatezaProfileCatalog::OPTIONAL_PROFILE_FIELDS).sort,
        fields.keys.sort
      )
      assert_equal DatezaProfileCatalog::REQUIRED_PREFERENCE_FIELDS.sort, preferences.keys.sort
      assert fields.fetch("bio").fetch(:required)
      assert_not fields.fetch("occupation").fetch(:required)
      assert_equal "textarea", fields.fetch("bio").fetch(:input_type)
      assert_equal "owner_only", fields.fetch("birthdate").fetch(:visibility)
      assert_equal %w[ never occasionally regularly ], fields.fetch("smoking").fetch(:options).pluck(:code)
      assert_includes fields.fetch("languages").fetch(:options).pluck(:code), "zu"
      assert_includes fields.fetch("languages").fetch(:options).pluck(:code), "tn"
    end
  end
end
