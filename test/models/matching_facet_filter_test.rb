require "test_helper"

module Matching
  class FacetFilterTest < ActiveSupport::TestCase
    setup do
      @brand = Brand.create!(slug: "configurable", name: "Configurable")
      @group = ProfileOptionGroup.create!(
        brand: @brand, key: "energy", label: "Energy", visibility: :public_profile
      )
      @calm = ProfileOption.create!(
        brand: @brand, profile_option_group: @group, code: "calm", label: "Calm"
      )
      @selected = create_profile
      @other = create_profile
      ProfileOptionSelection.create!(
        profile: @selected, user: @selected.user, brand: @brand,
        profile_option_group: @group, profile_option: @calm
      )
    end

    test "filters through a configured option group without knowing its product meaning" do
      definitions = [ { type: :option_group, parameter: :mood, option_group: "energy" } ]
      filter = FacetFilter.parse(
        brand: @brand, definitions:, params: { mood: "calm", vibe: "ignored_unconfigured_value" }
      )

      result = FacetFilter.apply(scope: @brand.profiles, brand: @brand, filter:)

      assert_equal [ @selected.id ], result.pluck(:id)
      assert_equal "mood:calm", filter.cursor_key
      assert_raises(FacetFilter::InvalidFilter) do
        FacetFilter.parse(brand: @brand, definitions:, params: { mood: "unknown" })
      end
    end

    test "preserves the existing HookUs facet cursor fingerprint" do
      hookus = Brand.create!(slug: "hookus", name: "HookUs")
      Profiles::HookusProfileCatalog.install!(brand: hookus)
      definitions = D8n::Platform::Brands::Hookus::FACETS

      filter = FacetFilter.parse(
        brand: hookus, definitions:, params: { vibe: "420_friendly", online: "true" }
      )

      assert_equal "vibe:420_friendly|online:1", filter.cursor_key
    end

    private

    def create_profile
      user = User.create!
      membership = BrandMembership.create!(brand: @brand, user:)
      Profile.create!(
        brand: @brand, user:, brand_membership: membership,
        status: :active, visibility: :visible, birthdate: 30.years.ago.to_date, gender: "person"
      )
    end
  end
end
