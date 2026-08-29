require "test_helper"

class Hq::Identity::LookupTest < ActiveSupport::TestCase
  setup do
    @brand = Brand.create!(slug: "hookus", name: "HookUs")
    @user = User.create!
    @membership = BrandMembership.create!(brand: @brand, user: @user)
    @profile = Profile.create!(
      brand: @brand, user: @user, brand_membership: @membership, display_name: "Ada",
      birthdate: 30.years.ago.to_date, gender: "person", status: :active, visibility: :visible
    )
    @email = IdentityIdentifier.create!(user: @user, kind: :email, normalized_value: "ada@example.com")
    @phone = IdentityIdentifier.create!(user: @user, kind: :phone, normalized_value: "27821234567")
  end

  test "resolves a member by email" do
    result = Hq::Identity::Lookup.call(brand: @brand, lookup: "ADA@example.com")

    assert_equal @user, result.user
    assert_equal @membership, result.brand_membership
    assert_equal @profile, result.profile
  end

  test "resolves a member by phone" do
    result = Hq::Identity::Lookup.call(brand: @brand, lookup: "27821234567")

    assert_equal @user, result.user
  end

  test "resolves a member by profile public_id" do
    result = Hq::Identity::Lookup.call(brand: @brand, lookup: @profile.public_id)

    assert_equal @user, result.user
    assert_equal @profile, result.profile
  end

  test "resolves a member without a profile yet, by email" do
    bare_user = User.create!
    BrandMembership.create!(brand: @brand, user: bare_user)
    IdentityIdentifier.create!(user: bare_user, kind: :email, normalized_value: "bare@example.com")

    result = Hq::Identity::Lookup.call(brand: @brand, lookup: "bare@example.com")

    assert_equal bare_user, result.user
    assert_nil result.profile
  end

  test "returns nil for an unknown identifier" do
    assert_nil Hq::Identity::Lookup.call(brand: @brand, lookup: "nobody@example.com")
    assert_nil Hq::Identity::Lookup.call(brand: @brand, lookup: SecureRandom.uuid)
    assert_nil Hq::Identity::Lookup.call(brand: @brand, lookup: "")
    assert_nil Hq::Identity::Lookup.call(brand: @brand, lookup: "   ")
  end

  test "returns nil (not the other brand's data) when the identifier belongs to another brand only" do
    other_brand = Brand.create!(slug: "other", name: "Other")
    other_user = User.create!
    BrandMembership.create!(brand: other_brand, user: other_user)
    IdentityIdentifier.create!(user: other_user, kind: :email, normalized_value: "cross@example.com")
    Profile.create!(
      brand: other_brand, user: other_user,
      brand_membership: BrandMembership.find_by(brand: other_brand, user: other_user),
      display_name: "Cross", birthdate: 30.years.ago.to_date, gender: "person", status: :active, visibility: :visible
    )

    assert_nil Hq::Identity::Lookup.call(brand: @brand, lookup: "cross@example.com")
    assert_nil Hq::Identity::Lookup.call(
      brand: @brand,
      lookup: Profile.find_by(brand: other_brand, user: other_user).public_id
    )
  end

  test "a member with an identifier but no membership on this brand is not found" do
    other_brand = Brand.create!(slug: "other", name: "Other")
    result = Hq::Identity::Lookup.call(brand: other_brand, lookup: "ada@example.com")

    assert_nil result
  end
end
