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

  test "authentication methods deny by default and accept the supported allow-list" do
    brand = Brand.create!(slug: "hookus", name: "HookUs")
    assert_empty brand.auth_methods

    brand.update!(auth_methods: %w[ phone_password email_password google ])
    assert_equal %w[ phone_password email_password google ], brand.auth_methods
  end

  test "rejects duplicate, malformed, and unsupported authentication methods" do
    duplicate = Brand.new(slug: "duplicate", name: "Duplicate", auth_methods: %w[ phone_password phone_password ])
    malformed = Brand.new(slug: "malformed", name: "Malformed", auth_methods: "phone_password")
    unsupported = Brand.new(slug: "unsupported", name: "Unsupported", auth_methods: %w[ magic_link ])

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:auth_methods], "contains duplicates"
    assert_not malformed.valid?
    assert_includes malformed.errors[:auth_methods], "must be a list of supported strings"
    assert_not unsupported.valid?
    assert_includes unsupported.errors[:auth_methods], "contains unsupported methods"
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
