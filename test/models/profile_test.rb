require "test_helper"

class ProfileTest < ActiveSupport::TestCase
  test "allows one active profile per user and brand" do
    brand = Brand.create!(slug: "hookus", name: "HookUs")
    user = User.create!
    membership = BrandMembership.create!(user:, brand:)

    Profile.create!(user:, brand:, brand_membership: membership, display_name: "Ada")
    duplicate = Profile.new(user:, brand:, brand_membership: membership, display_name: "Ada 2")

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:user_id], "has already been taken"
  end

  test "requires brand membership to match user and brand" do
    brand = Brand.create!(slug: "hookus", name: "HookUs")
    other_brand = Brand.create!(slug: "date9ja", name: "Date9ja")
    user = User.create!
    membership = BrandMembership.create!(user:, brand: other_brand)

    profile = Profile.new(user:, brand:, brand_membership: membership, display_name: "Ada")

    assert_not profile.valid?
    assert_includes profile.errors[:brand_membership], "must belong to the same user and brand"
  end

  test "soft-deleted profiles do not block replacement" do
    brand = Brand.create!(slug: "hookus", name: "HookUs")
    user = User.create!
    membership = BrandMembership.create!(user:, brand:)
    Profile.create!(
      user:,
      brand:,
      brand_membership: membership,
      display_name: "Old",
      deleted_at: Time.current
    )

    replacement = Profile.new(user:, brand:, brand_membership: membership, display_name: "New")

    assert replacement.valid?
  end

  test "requires birthdate to meet the minimum age floor" do
    brand = Brand.create!(slug: "hookus", name: "HookUs")
    user = User.create!
    membership = BrandMembership.create!(user:, brand:)
    profile = Profile.new(
      user:,
      brand:,
      brand_membership: membership,
      birthdate: 17.years.ago.to_date
    )

    assert_not profile.valid?
    assert_includes profile.errors[:birthdate], "must be at least 18 years ago"
  end
end
