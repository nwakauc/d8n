require "test_helper"

class ProfileVideoTest < ActiveSupport::TestCase
  setup do
    @brand = Brand.create!(slug: "date9ja", name: "Date9ja")
    @user = User.create!
    @membership = BrandMembership.create!(brand: @brand, user: @user)
    @profile = Profile.create!(
      brand: @brand, user: @user, brand_membership: @membership,
      display_name: "Ada", birthdate: 26.years.ago.to_date, gender: "woman"
    )
  end

  def new_video(**overrides)
    ProfileVideo.new({ profile: @profile, user: @user, brand: @brand }.merge(overrides)).tap do |record|
      record.video.attach(
        io: StringIO.new("x"), filename: "v.mp4", content_type: "video/mp4"
      )
    end
  end

  test "assigns an opaque public id and persists" do
    video = new_video
    assert video.save
    assert_match Profile::PUBLIC_ID_FORMAT, video.public_id
    assert video.processing_pending?
    assert video.pending_review?
  end

  test "requires an attached video on create" do
    record = ProfileVideo.new(profile: @profile, user: @user, brand: @brand)
    assert_not record.valid?
    assert_includes record.errors[:video], "must be attached"
  end

  test "rejects a profile from another user or brand" do
    other_user = User.create!
    other = Profile.create!(
      brand: @brand, user: other_user, brand_membership: BrandMembership.create!(brand: @brand, user: other_user),
      display_name: "B", birthdate: 30.years.ago.to_date, gender: "man"
    )
    video = new_video(profile: other) # profile.user_id != @user.id
    assert_not video.valid?
    assert_includes video.errors[:profile], "must belong to the same user and brand"
  end

  test "the one-per-profile partial unique index blocks a second live video" do
    new_video.save!
    assert_raises(ActiveRecord::RecordNotUnique) do
      new_video(public_id: SecureRandom.uuid).save!(validate: false)
    end
  end

  test "a soft-deleted video frees the slot for a new one" do
    first = new_video
    first.save!
    first.update!(deleted_at: Time.current)

    assert_nothing_raised { new_video.save! }
  end

  test "deliverable? requires a ready safe rendition + poster, visible, not rejected" do
    video = new_video
    video.save!
    assert_not video.deliverable?, "no rendition yet"

    video.playback.attach(io: StringIO.new("y"), filename: "playback.mp4", content_type: "video/mp4")
    video.update!(processing_state: :ready, visibility: :visible, status: :pending_review)
    assert_not video.deliverable?, "ready with a rendition but no poster is still not deliverable"

    video.poster.attach(io: StringIO.new("p"), filename: "poster.jpg", content_type: "image/jpeg")
    assert video.reload.deliverable?

    video.update!(status: :rejected)
    assert_not video.deliverable?
  end
end
