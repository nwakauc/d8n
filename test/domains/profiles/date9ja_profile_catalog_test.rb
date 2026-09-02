require "test_helper"

module Profiles
  class Date9jaProfileCatalogTest < ActiveSupport::TestCase
    setup { @brand = Brand.create!(slug: "date9ja", name: "Date9ja") }

    test "installs the non-sensitive option groups, interests and prompts idempotently" do
      Date9jaProfileCatalog.install!(brand: @brand)

      assert_no_difference [
        -> { ProfileOptionGroup.count }, -> { ProfileOption.count }, -> { ProfilePrompt.count }
      ] do
        Date9jaProfileCatalog.install!(brand: @brand)
      end

      groups = @brand.profile_option_groups.kept.pluck(:key)
      assert_includes groups, "relationship_intent"
      assert_includes groups, "interests"
      assert_equal Date9jaProfileCatalog::ENABLED_PROMPTS.sort,
        @brand.profile_prompts.kept.pluck(:key).sort
    end

    test "produces brand profile requirements the Brand model accepts" do
      Date9jaProfileCatalog.install!(brand: @brand)

      assert @brand.valid?, @brand.errors.full_messages.to_sentence
      requirements = @brand.profile_completion_requirements
      assert_equal Date9jaProfileCatalog::REQUIRED_PROFILE_FIELDS, requirements.fetch("profile_fields")
      assert_equal %w[photos location], requirements.fetch("collections")
    end

    test "models no sensitive field and keeps family fields owner-only" do
      Date9jaProfileCatalog.install!(brand: @brand)

      sensitive = %w[religion ethnicity tribe denomination preferred_tribes genotype religion_importance]
      assert_empty(@brand.profile_option_groups.kept.pluck(:key) & sensitive)

      %w[has_children wants_children].each do |key|
        group = @brand.profile_option_groups.kept.find_by!(key:)
        assert_equal "owner_only", group.visibility
      end
    end

    test "curates the interests taxonomy down to the Date9ja subset" do
      Date9jaProfileCatalog.install!(brand: @brand)

      codes = @brand.profile_option_groups.kept.find_by!(key: "interests")
        .profile_options.kept.status_active.pluck(:code)
      assert_equal Date9jaProfileCatalog::INTERESTS.sort, codes.sort
      assert_includes codes, "afrobeats"
    end
  end
end
