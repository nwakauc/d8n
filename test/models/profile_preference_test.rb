require "test_helper"

class ProfilePreferenceTest < ActiveSupport::TestCase
  test "allows one active preference record per profile" do
    brand, user, profile = profile_setup
    ProfilePreference.create!(brand:, user:, profile:, min_age: 25, max_age: 35)
    duplicate = ProfilePreference.new(brand:, user:, profile:, min_age: 30, max_age: 40)

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:profile_id], "has already been taken"
  end

  test "requires profile to match user and brand" do
    brand, user, = profile_setup
    other_brand, _, other_profile = profile_setup(slug: "date9ja", user:)
    preference = ProfilePreference.new(
      brand:,
      user:,
      profile: other_profile,
      min_age: 25,
      max_age: 35
    )

    assert_not preference.valid?
    assert_equal other_brand, other_profile.brand
    assert_includes preference.errors[:profile], "must belong to the same user and brand"
  end

  test "database rejects preferences assigned to a different brand than their profile" do
    _, user, profile = profile_setup
    other_brand = Brand.create!(slug: "date9ja", name: "Date9ja")

    assert_raises ActiveRecord::InvalidForeignKey do
      ProfilePreference.insert_all!([ {
        profile_id: profile.id,
        user_id: user.id,
        brand_id: other_brand.id,
        interested_in: [],
        metadata: {},
        created_at: Time.current,
        updated_at: Time.current
      } ])
    end
  end

  test "validates age range and distance limits" do
    brand, user, profile = profile_setup
    preference = ProfilePreference.new(
      brand:,
      user:,
      profile:,
      min_age: 17,
      max_age: 16,
      max_distance_km: 501
    )

    assert_not preference.valid?
    assert preference.errors[:min_age].present?
    assert_includes preference.errors[:max_age], "must be greater than or equal to min_age"
    assert preference.errors[:max_distance_km].present?
  end

  test "requires interested_in to be an array" do
    brand, user, profile = profile_setup
    preference = ProfilePreference.new(brand:, user:, profile:, interested_in: "woman")

    assert_not preference.valid?
    assert_includes preference.errors[:interested_in], "must be an array"
  end

  private

  def profile_setup(slug: "hookus", user: User.create!)
    brand = Brand.create!(slug:, name: slug.titleize)
    membership = BrandMembership.create!(brand:, user:)
    profile = Profile.create!(
      brand:,
      user:,
      brand_membership: membership,
      display_name: "Ada",
      birthdate: 25.years.ago.to_date
    )

    [ brand, user, profile ]
  end
end
