require "test_helper"

module Profiles
  class HookusProfileCatalogTest < ActiveSupport::TestCase
    test "installs the required HookUs option groups idempotently" do
      brand = Brand.create!(slug: "hookus", name: "HookUs")

      assert_difference -> { ProfileOptionGroup.count }, 2 do
        HookusProfileCatalog.install!(brand:)
      end
      assert_no_difference [ -> { ProfileOptionGroup.count }, -> { ProfileOption.count } ] do
        HookusProfileCatalog.install!(brand:)
      end

      requirements = brand.reload.profile_completion_requirements
      assert_equal %w[ intents vibes ], requirements.fetch("option_groups")
      assert_includes requirements.fetch("profile_fields"), "bio"
      assert_includes requirements.fetch("profile_fields"), "country_code"
      assert_equal %w[ interested_in ], requirements.fetch("preference_fields")
      assert_equal 8, brand.profile_option_groups.find_by!(key: "intents").profile_options.count
      assert_equal 15, brand.profile_option_groups.find_by!(key: "vibes").profile_options.count
    end
  end
end
