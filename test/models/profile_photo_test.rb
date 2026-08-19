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

  test "database rejects photos assigned to a different brand than their profile" do
    _, user, profile = profile_setup
    other_brand = Brand.create!(slug: "date9ja", name: "Date9ja")

    assert_raises ActiveRecord::InvalidForeignKey do
      ProfilePhoto.insert_all!([ {
        public_id: SecureRandom.uuid,
        profile_id: profile.id,
        user_id: user.id,
        brand_id: other_brand.id,
        position: 0,
        status: ProfilePhoto.statuses.fetch("pending_review"),
        visibility: ProfilePhoto.visibilities.fetch("hidden"),
        metadata: {},
        created_at: Time.current,
        updated_at: Time.current
      } ])
    end
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
