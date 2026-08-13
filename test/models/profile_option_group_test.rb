require "test_helper"

class ProfileOptionGroupTest < ActiveSupport::TestCase
  test "requires single-select groups to allow exactly one selection" do
    group = ProfileOptionGroup.new(
      brand: Brand.create!(slug: "hookus", name: "HookUs"),
      key: "relationship_intent",
      label: "Relationship intent",
      cardinality: :single,
      max_selections: 2
    )

    assert_not group.valid?
    assert_includes group.errors[:max_selections], "must be 1 for a single-select group"
  end

  test "does not allow a stable group key to change" do
    group = ProfileOptionGroup.create!(
      brand: Brand.create!(slug: "hookus", name: "HookUs"),
      key: "vibes",
      label: "Vibes",
      cardinality: :multiple,
      max_selections: 15
    )

    group.key = "moods"

    assert_not group.valid?
    assert_includes group.errors[:key], "cannot be changed"
  end

  test "does not retire a group while the brand requires it" do
    brand = Brand.create!(slug: "hookus", name: "HookUs")
    Profiles::HookusProfileCatalog.install!(brand:)
    group = brand.profile_option_groups.find_by!(key: "vibes")

    group.status = :retired

    assert_not group.valid?
    assert_includes group.errors[:base], "required option groups cannot be retired or deleted"
  end
end
