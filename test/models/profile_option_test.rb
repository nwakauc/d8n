require "test_helper"

class ProfileOptionTest < ActiveSupport::TestCase
  test "requires the option group to belong to the same brand" do
    hookus = Brand.create!(slug: "hookus", name: "HookUs")
    date9ja = Brand.create!(slug: "date9ja", name: "Date9ja")
    group = ProfileOptionGroup.create!(brand: hookus, key: "vibes", label: "Vibes")
    option = ProfileOption.new(brand: date9ja, profile_option_group: group, code: "chill", label: "Chill")

    assert_not option.valid?
    assert_includes option.errors[:profile_option_group], "must belong to the same brand"
  end

  test "allows labels to change but keeps machine codes immutable" do
    brand = Brand.create!(slug: "hookus", name: "HookUs")
    group = ProfileOptionGroup.create!(brand:, key: "vibes", label: "Vibes")
    option = ProfileOption.create!(brand:, profile_option_group: group, code: "night_owl", label: "Night owl")

    option.update!(label: "Up late")
    option.code = "late_night"

    assert_not option.valid?
    assert_includes option.errors[:code], "cannot be changed"
  end
end
