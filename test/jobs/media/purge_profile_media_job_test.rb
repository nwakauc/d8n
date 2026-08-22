require "test_helper"

class Media::PurgeProfileMediaJobTest < ActiveJob::TestCase
  setup do
    @brand = Brand.create!(slug: "hookus", name: "HookUs")
    @user = User.create!
    @membership = BrandMembership.create!(brand: @brand, user: @user)
    @profile = Profile.create!(brand: @brand, user: @user, brand_membership: @membership,
      birthdate: 30.years.ago.to_date, gender: "person", status: :active, visibility: :visible)
    @closure = AccountClosure.create!(brand: @brand, user: @user, brand_membership: @membership, profile: @profile)
  end

  test "purges every photo's attachments across mixed states and completes the closure" do
    ready = build_photo(position: 0)
    ready.display_image.attach(io: StringIO.new("derivative"), filename: "d.jpg", content_type: "image/jpeg")
    ready.update!(processing_state: :ready)
    pending = build_photo(position: 1) # raw only, no derivative
    failed = build_photo(position: 2)
    failed.update!(processing_state: :failed)
    ready.update!(deleted_at: Time.current) # already soft-deleted is still purged

    Media::PurgeProfileMediaJob.perform_now(@closure.id)

    [ ready, pending, failed ].each do |photo|
      assert_not photo.reload.image.attached?
      assert_not photo.display_image.attached?
    end
    assert @closure.reload.media_purge_completed?
    assert @closure.media_purged_at.present?
  end

  test "a repeated purge is idempotent" do
    build_photo(position: 0)
    Media::PurgeProfileMediaJob.perform_now(@closure.id)

    assert_nothing_raised do
      Media::PurgeProfileMediaJob.perform_now(@closure.id)
    end
    assert @closure.reload.media_purge_completed?
  end

  test "an already-missing object does not break the purge" do
    photo = build_photo(position: 0)
    photo.image.blob.service.delete(photo.image.blob.key) # object vanished underneath us

    assert_nothing_raised { Media::PurgeProfileMediaJob.perform_now(@closure.id) }
    assert @closure.reload.media_purge_completed?
    assert_not photo.reload.image.attached?
  end

  test "purges from the blob's persisted brand service" do
    service = ActiveStorage::Blob.services.fetch(:brand_test)
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("brand raw"), filename: "a.jpg", content_type: "image/jpeg",
      service_name: "brand_test"
    )
    photo = ProfilePhoto.new(profile: @profile, user: @user, brand: @brand)
    photo.image.attach(blob)
    photo.save!
    key = blob.key

    assert service.exist?(key)
    Media::PurgeProfileMediaJob.perform_now(@closure.id)

    assert_not service.exist?(key)
    assert_not photo.reload.image.attached?
  end

  test "a closure with no profile completes immediately" do
    profileless = AccountClosure.create!(brand: @brand, user: User.create!,
      brand_membership: BrandMembership.create!(brand: @brand, user: User.create!))

    Media::PurgeProfileMediaJob.perform_now(profileless.id)
    assert profileless.reload.media_purge_completed?
  end

  test "an already-completed closure is skipped" do
    @closure.update!(media_purge_state: :completed, media_purged_at: 1.day.ago)
    photo = build_photo(position: 0)

    Media::PurgeProfileMediaJob.perform_now(@closure.id)
    # Not re-processed: the attachment is untouched.
    assert photo.reload.image.attached?
  end

  private

  def build_photo(position:)
    photo = ProfilePhoto.new(profile: @profile, user: @user, brand: @brand, position:)
    photo.image.attach(io: StringIO.new("raw#{position}"), filename: "a.jpg", content_type: "image/jpeg")
    photo.save!
    photo
  end
end
