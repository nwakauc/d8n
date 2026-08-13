require "test_helper"

class ProfileOptionSelectionTest < ActiveSupport::TestCase
  test "rejects tenant-mismatched selections in the model and database" do
    hookus, user, profile, group, option = option_setup
    date9ja = Brand.create!(slug: "date9ja", name: "Date9ja")
    selection = ProfileOptionSelection.new(
      profile:,
      user:,
      brand: date9ja,
      profile_option_group: group,
      profile_option: option
    )

    assert_not selection.valid?
    assert_includes selection.errors[:profile], "must belong to the same user and brand"

    assert_raises ActiveRecord::InvalidForeignKey do
      ProfileOptionSelection.insert_all!([ {
        profile_id: profile.id,
        user_id: user.id,
        brand_id: date9ja.id,
        profile_option_group_id: group.id,
        profile_option_id: option.id,
        created_at: Time.current,
        updated_at: Time.current
      } ])
    end

    assert_equal hookus, profile.brand
  end

  test "prevents new selections of retired options but preserves existing selections" do
    brand, user, profile, group, option = option_setup
    selection = ProfileOptionSelection.create!(
      profile:, user:, brand:, profile_option_group: group, profile_option: option
    )
    option.update!(status: :retired)

    assert_equal selection, ProfileOptionSelection.kept.find(selection.id)

    other_option = ProfileOption.create!(
      brand:, profile_option_group: group, code: "music", label: "Music", status: :retired
    )
    rejected = ProfileOptionSelection.new(
      profile:, user:, brand:, profile_option_group: group, profile_option: other_option
    )

    assert_not rejected.valid?
    assert_includes rejected.errors[:profile_option], "must be active"
  end

  test "database rejects an option assigned through the wrong group" do
    brand, user, profile, group, = option_setup
    other_group = ProfileOptionGroup.create!(
      brand:, key: "intents", label: "Intents", cardinality: :multiple, max_selections: 5
    )
    other_option = ProfileOption.create!(
      brand:, profile_option_group: other_group, code: "casual", label: "Casual"
    )

    assert_raises ActiveRecord::InvalidForeignKey do
      ProfileOptionSelection.insert_all!([ {
        profile_id: profile.id,
        user_id: user.id,
        brand_id: brand.id,
        profile_option_group_id: group.id,
        profile_option_id: other_option.id,
        created_at: Time.current,
        updated_at: Time.current
      } ])
    end
  end

  test "enforces the group selection limit" do
    brand, user, profile, group, option = option_setup(max_selections: 1)
    ProfileOptionSelection.create!(profile:, user:, brand:, profile_option_group: group, profile_option: option)
    second_option = ProfileOption.create!(brand:, profile_option_group: group, code: "music", label: "Music")
    second = ProfileOptionSelection.new(
      profile:, user:, brand:, profile_option_group: group, profile_option: second_option
    )

    assert_not second.valid?
    assert_includes second.errors[:profile_option_group], "allows at most 1 selections"
  end

  private

  def option_setup(max_selections: 15)
    brand = Brand.create!(slug: "hookus", name: "HookUs")
    user = User.create!
    membership = BrandMembership.create!(brand:, user:)
    profile = Profile.create!(brand:, user:, brand_membership: membership)
    group = ProfileOptionGroup.create!(
      brand:, key: "vibes", label: "Vibes", cardinality: :multiple, max_selections:
    )
    option = ProfileOption.create!(brand:, profile_option_group: group, code: "chill", label: "Chill")

    [ brand, user, profile, group, option ]
  end
end
