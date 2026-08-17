require "test_helper"
require "vips"

module Media
  class ProcessProfilePhotoJobTest < ActiveJob::TestCase
    test "generates a safe derivative, marks ready, and purges the raw original" do
      photo = photo_with_raw

      perform_enqueued_jobs { ProcessProfilePhotoJob.perform_now(photo.id) }

      photo.reload
      assert photo.processing_ready?
      assert photo.processed_at.present?
      assert photo.display_image.attached?
      assert_equal "image/jpeg", photo.display_image.blob.content_type
      assert_not photo.image.attached?, "raw original must be purged once the derivative exists"
      # The derivative is a genuinely decodable image.
      decoded = Vips::Image.new_from_buffer(photo.display_image.download, "")
      assert_operator decoded.width, :>, 0
    end

    test "is idempotent across duplicate executions" do
      photo = photo_with_raw

      perform_enqueued_jobs { ProcessProfilePhotoJob.perform_now(photo.id) }
      display_blob_id = photo.reload.display_image.blob.id
      # A duplicate run must not create a second derivative or raise.
      perform_enqueued_jobs { ProcessProfilePhotoJob.perform_now(photo.id) }

      assert photo.reload.processing_ready?
      assert_equal display_blob_id, photo.display_image.blob.id
    end

    test "no-ops when the photo was soft-deleted before processing" do
      photo = photo_with_raw
      photo.update!(deleted_at: Time.current)

      assert_nothing_raised do
        perform_enqueued_jobs { ProcessProfilePhotoJob.perform_now(photo.id) }
      end

      assert_not photo.reload.processing_ready?
      assert_not photo.display_image.attached?
    end

    test "no-ops when the photo record no longer exists" do
      assert_nothing_raised { ProcessProfilePhotoJob.perform_now(-1) }
    end

    test "records a terminal failure for an undecodable image without retrying forever" do
      photo = photo_with_raw(bytes: "not a real image", content_type: "image/jpeg")

      perform_enqueued_jobs { ProcessProfilePhotoJob.perform_now(photo.id) }

      photo.reload
      assert photo.processing_failed?
      assert_not photo.display_image.attached?, "a failed image produces no deliverable derivative"
      assert photo.image.attached?, "raw is retained on failure so the owner still sees their upload"
    end

    private

    def valid_jpeg
      @valid_jpeg ||= Vips::Image.black(120, 90).add([ 110 ]).cast("uchar").write_to_buffer(".jpg")
    end

    def photo_with_raw(bytes: nil, content_type: "image/jpeg")
      bytes ||= valid_jpeg
      brand = Brand.create!(slug: "hookus", name: "HookUs")
      user = User.create!
      membership = BrandMembership.create!(brand:, user:)
      profile = Profile.create!(
        brand:, user:, brand_membership: membership,
        display_name: "Ada", birthdate: 25.years.ago.to_date, gender: "woman"
      )
      # Mirror the real intent flow: the raw blob lands at the hierarchical
      # original key, so the derivative becomes a sibling display.jpg.
      key = Media::ObjectKey.profile_photo_original(brand:, user:, profile:, content_type:)
      blob = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new(bytes), key:, filename: "original.jpg",
        content_type:, service_name: ActiveStorage::Blob.service.name
      )
      photo = ProfilePhoto.new(brand:, user:, profile:)
      photo.image.attach(blob)
      photo.save!
      photo
    end
  end
end
