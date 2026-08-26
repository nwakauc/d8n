require "test_helper"

module Profiles
  class OptionSelectionsTest < ActiveSupport::TestCase
    setup do
      @brand = Brand.create!(slug: "hookus", name: "HookUs")
      HookusProfileCatalog.install!(brand: @brand)
      @user = User.create!
      membership = BrandMembership.create!(brand: @brand, user: @user)
      @profile = Profile.create!(brand: @brand, user: @user, brand_membership: membership)
    end

    test "replaces only the supplied option groups and soft deletes removed selections" do
      OptionSelections.replace!(profile: @profile, selections: {
        intents: %w[ hookups casual ],
        vibes: %w[ chill music ]
      })

      assert_equal 4, @profile.profile_option_selections.kept.count

      OptionSelections.replace!(profile: @profile, selections: { intents: [ "relationship" ] })

      assert_equal [ "relationship" ], selected_codes("intents")
      assert_equal %w[ music chill ], selected_codes("vibes")
      assert_equal 2, @profile.profile_option_selections.where.not(deleted_at: nil).count
    end

    test "an explicit empty array clears a group while omitted groups stay untouched" do
      OptionSelections.replace!(profile: @profile, selections: {
        intents: %w[ hookups casual ],
        vibes: %w[ chill music ]
      })

      OptionSelections.replace!(profile: @profile, selections: { intents: [] })

      assert_empty selected_codes("intents")
      assert_equal %w[ music chill ], selected_codes("vibes"), "omitted group is unaffected by clearing another"
    end

    test "rejects unknown groups and retired options" do
      error = assert_raises OptionSelections::InvalidSelection do
        OptionSelections.replace!(profile: @profile, selections: { unknown: [ "value" ] })
      end
      assert_equal [ "is not enabled for this brand" ], error.details.fetch("unknown")

      option = @brand.profile_options.find_by!(code: "chill")
      option.update!(status: :retired)

      assert_raises OptionSelections::InvalidSelection do
        OptionSelections.replace!(profile: @profile, selections: { vibes: [ "chill" ] })
      end
    end

    test "does not select an option from another brand with the same code" do
      other_brand = Brand.create!(slug: "date9ja", name: "Date9ja")
      other_group = ProfileOptionGroup.create!(
        brand: other_brand, key: "vibes", label: "Vibes", cardinality: :multiple, max_selections: 5
      )
      ProfileOption.create!(brand: other_brand, profile_option_group: other_group, code: "date9ja_only", label: "Date9ja")

      assert_raises OptionSelections::InvalidSelection do
        OptionSelections.replace!(profile: @profile, selections: { vibes: [ "date9ja_only" ] })
      end
      assert_empty @profile.profile_option_selections.kept
    end

    private

    def selected_codes(group_key)
      @profile.profile_option_selections.kept.joins(:profile_option_group, :profile_option)
        .where(profile_option_groups: { key: group_key }).order("profile_options.position").pluck("profile_options.code")
    end
  end
end
