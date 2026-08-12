require "test_helper"

class ProfilePhotoTest < ActiveSupport::TestCase
  test "requires attached image" do
    brand, user, profile = profile_setup
    photo = ProfilePhoto.new(brand:, user:, profile:)

    assert_not photo.valid?
    assert_includes photo.errors[:image], "must be attached"
  end

  test "requires profile to match user and brand" do
    brand, user, = profile_setup
    _, _, other_profile = profile_setup(slug: "date9ja", user:)
    photo = ProfilePhoto.new(brand:, user:, profile: other_profile)
    attach_image(photo)

    assert_not photo.valid?
    assert_includes photo.errors[:profile], "must belong to the same user and brand"
  end

  test "accepts supported image content types" do
    brand, user, profile = profile_setup
    photo = ProfilePhoto.new(brand:, user:, profile:)
    attach_image(photo, content_type: "image/png")

    assert photo.valid?
  end

  test "rejects unsupported content types" do
    brand, user, profile = profile_setup
    photo = ProfilePhoto.new(brand:, user:, profile:)
    attach_image(photo, content_type: "text/plain")

    assert_not photo.valid?
    assert_includes photo.errors[:image], "must be a JPEG, PNG, or WebP image"
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
      birthdate: 25.years.ago.to_date,
      gender: "woman"
    )

    [ brand, user, profile ]
  end

  def attach_image(photo, content_type: "image/png")
    photo.image.attach(
      io: Rails.root.join("test/fixtures/files/profile_photo.png").open,
      filename: "profile_photo.png",
      content_type:
    )
  end
end
