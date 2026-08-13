require "test_helper"

class BrandTest < ActiveSupport::TestCase
  test "requires slug and name" do
    brand = Brand.new

    assert_not brand.valid?
    assert_includes brand.errors[:slug], "can't be blank"
    assert_includes brand.errors[:name], "can't be blank"
  end

  test "enforces unique active slug" do
    Brand.create!(slug: "hookus", name: "HookUs")
    duplicate = Brand.new(slug: "hookus", name: "HookUs Copy")

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:slug], "has already been taken"
  end

  test "allows slug reuse after soft deletion" do
    Brand.create!(slug: "hookus", name: "HookUs", deleted_at: Time.current)
    brand = Brand.new(slug: "hookus", name: "HookUs")

    assert brand.valid?
  end

  test "defaults profile completion requirements" do
    brand = Brand.create!(slug: "hookus", name: "HookUs")

    assert_equal %w[ display_name birthdate gender ], brand.profile_completion_requirements.fetch("profile_fields")
    assert_equal %w[ min_age max_age interested_in ], brand.profile_completion_requirements.fetch("preference_fields")
    assert_equal %w[ photos ], brand.profile_completion_requirements.fetch("collections")
    assert_empty brand.profile_completion_requirements.fetch("option_groups")
  end

  test "rejects unsupported profile completion requirements" do
    brand = Brand.new(
      slug: "hookus",
      name: "HookUs",
      profile_requirements: {
        profile_fields: [ "display_name", "unknown_field" ],
        preference_fields: [ "min_age" ],
        collections: []
      }
    )

    assert_not brand.valid?
    assert_includes brand.errors[:profile_requirements], "contains unsupported profile fields"
  end

  test "rejects malformed profile completion requirements" do
    brand = Brand.new(slug: "hookus", name: "HookUs", profile_requirements: { profile_fields: "display_name" })

    assert_not brand.valid?
    assert_includes brand.errors[:profile_requirements], "must contain only supported string lists"
  end
end
