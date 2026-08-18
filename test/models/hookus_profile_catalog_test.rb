require "test_helper"

module Profiles
  class HookusProfileCatalogTest < ActiveSupport::TestCase
    test "installs brand groups plus composed generic capabilities idempotently" do
      brand = Brand.create!(slug: "hookus", name: "HookUs")
      expected_groups = HookusProfileCatalog::BRAND_GROUPS.size +
        HookusProfileCatalog::ENABLED_CAPABILITIES.size + 1 # + interests

      assert_difference -> { ProfileOptionGroup.count }, expected_groups do
        assert_difference -> { ProfilePrompt.count }, HookusProfileCatalog::ENABLED_PROMPTS.size do
          HookusProfileCatalog.install!(brand:)
        end
      end

      # Re-running installs nothing new (idempotent) across every capability table.
      assert_no_difference [
        -> { ProfileOptionGroup.count }, -> { ProfileOption.count }, -> { ProfilePrompt.count }
      ] do
        HookusProfileCatalog.install!(brand:)
      end

      requirements = brand.reload.profile_completion_requirements
      # Only the original brand groups remain REQUIRED — new capabilities are optional.
      assert_equal %w[ intents vibes ], requirements.fetch("option_groups")
      assert_includes requirements.fetch("profile_fields"), "bio"
      assert_includes requirements.fetch("profile_fields"), "country_code"
      assert_equal %w[ interested_in ], requirements.fetch("preference_fields")
      assert_equal %w[ phone_password email_password ], brand.auth_methods
      assert_equal 8, brand.profile_option_groups.find_by!(key: "intents").profile_options.count
      assert_equal 15, brand.profile_option_groups.find_by!(key: "vibes").profile_options.count
    end

    test "sensitive capabilities carry deliberate, non-default-public visibility" do
      brand = Brand.create!(slug: "hookus", name: "HookUs")
      HookusProfileCatalog.install!(brand:)

      groups = brand.profile_option_groups.kept.index_by(&:key)
      # HookUs deliberately opts orientation into public and cannabis into public.
      assert groups.fetch("sexual_orientation").visibility_public_profile?
      assert groups.fetch("cannabis").visibility_public_profile?
      assert_equal "420 friendly",
        groups.fetch("cannabis").profile_options.kept.find_by!(code: "friendly").label
      # Religion/children stay owner-only; intimacy stays matches-only.
      assert groups.fetch("religion").visibility_owner_only?
      assert groups.fetch("has_children").visibility_owner_only?
      assert groups.fetch("physical_affection").visibility_matches_only?
    end

    test "installs the categorized interests taxonomy and prompt set" do
      brand = Brand.create!(slug: "hookus", name: "HookUs")
      HookusProfileCatalog.install!(brand:)

      interests = brand.profile_option_groups.kept.find_by!(key: "interests")
      assert interests.visibility_public_profile?
      assert_equal CapabilityCatalog::INTERESTS.fetch(:options).size, interests.profile_options.kept.count
      assert_equal "food", interests.profile_options.kept.find_by!(code: "foodie").category
      assert_equal HookusProfileCatalog::ENABLED_PROMPTS.size, brand.profile_prompts.kept.count
    end
  end
end
