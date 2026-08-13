require "test_helper"

class ProfileLocationTest < ActiveSupport::TestCase
  test "accepts a tenant-consistent private location" do
    brand, user, profile = profile_setup
    location = ProfileLocation.new(
      brand:, user:, profile:, latitude: -33.9248685, longitude: 18.4240553,
      accuracy_meters: 25, source: "device", captured_at: Time.current
    )

    assert location.valid?
  end

  test "requires profile to match user and brand" do
    brand, user, = profile_setup
    _, _, other_profile = profile_setup(slug: "date9ja", user:)
    location = ProfileLocation.new(
      brand:, user:, profile: other_profile, latitude: -33.9, longitude: 18.4,
      accuracy_meters: 25, source: "device", captured_at: Time.current
    )

    assert_not location.valid?
    assert_includes location.errors[:profile], "must belong to the same user and brand"
  end

  test "database rejects a location assigned to another profile tenant" do
    _, user, profile = profile_setup
    other_brand = Brand.create!(slug: "date9ja", name: "Date9ja")

    assert_raises ActiveRecord::InvalidForeignKey do
      ProfileLocation.insert_all!([ {
        profile_id: profile.id,
        user_id: user.id,
        brand_id: other_brand.id,
        latitude: -33.9248685,
        longitude: 18.4240553,
        accuracy_meters: 25,
        source: "device",
        captured_at: Time.current,
        created_at: Time.current,
        updated_at: Time.current
      } ])
    end
  end

  test "allows one active location and permits replacement after soft deletion" do
    brand, user, profile = profile_setup
    existing = create_location(brand:, user:, profile:)
    duplicate = build_location(brand:, user:, profile:)

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:profile_id], "has already been taken"

    existing.update!(deleted_at: Time.current)

    assert build_location(brand:, user:, profile:).valid?
  end

  test "validates coordinate accuracy and capture time bounds" do
    brand, user, profile = profile_setup
    location = build_location(
      brand:, user:, profile:, latitude: -91, longitude: 181,
      accuracy_meters: ProfileLocation::MAX_ACCURACY_METERS + 1,
      captured_at: 6.minutes.from_now
    )

    assert_not location.valid?
    assert location.errors[:latitude].present?
    assert location.errors[:longitude].present?
    assert location.errors[:accuracy_meters].present?
    assert_includes location.errors[:captured_at], "cannot be more than five minutes in the future"
  end

  private

  def profile_setup(slug: "hookus", user: User.create!)
    brand = Brand.create!(slug:, name: slug.titleize)
    membership = BrandMembership.create!(brand:, user:)
    profile = Profile.create!(brand:, user:, brand_membership: membership)
    [ brand, user, profile ]
  end

  def create_location(**attributes)
    build_location(**attributes).tap(&:save!)
  end

  def build_location(latitude: -33.9248685, longitude: 18.4240553, accuracy_meters: 25,
    source: "device", captured_at: Time.current, **attributes)
    ProfileLocation.new(
      **attributes, latitude:, longitude:, accuracy_meters:, source:, captured_at:
    )
  end
end
