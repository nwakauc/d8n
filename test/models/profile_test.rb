require "test_helper"

class ProfileTest < ActiveSupport::TestCase
  test "assigns an unguessable public identifier" do
    brand = Brand.create!(slug: "hookus", name: "HookUs")
    user = User.create!
    membership = BrandMembership.create!(user:, brand:)

    profile = Profile.create!(user:, brand:, brand_membership: membership)

    assert_match(/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/, profile.public_id)
    assert_not_equal profile.id.to_s, profile.public_id
  end

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

  test "database rejects a profile whose membership belongs to another tenant" do
    brand = Brand.create!(slug: "hookus", name: "HookUs")
    other_brand = Brand.create!(slug: "date9ja", name: "Date9ja")
    user = User.create!
    membership = BrandMembership.create!(user:, brand: other_brand)

    assert_raises ActiveRecord::InvalidForeignKey do
      Profile.insert_all!([ {
        user_id: user.id,
        brand_id: brand.id,
        brand_membership_id: membership.id,
        status: Profile.statuses.fetch("draft"),
        visibility: Profile.visibilities.fetch("hidden"),
        metadata: {},
        created_at: Time.current,
        updated_at: Time.current
      } ])
    end
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

  test "normalizes and validates HookUs profile details" do
    brand = Brand.create!(slug: "hookus", name: "HookUs")
    user = User.create!
    membership = BrandMembership.create!(user:, brand:)
    profile = Profile.new(
      user:, brand:, brand_membership: membership,
      country_code: " za ", city: " Johannesburg ", languages_spoken: [ "English", " English ", "Zulu" ],
      height_cm: 99, smoking: "sometimes"
    )

    assert_not profile.valid?
    assert_equal "ZA", profile.country_code
    assert_equal "Johannesburg", profile.city
    assert_equal %w[ English Zulu ], profile.languages_spoken
    assert profile.errors[:height_cm].present?
    assert profile.errors[:smoking].present?
  end
end
