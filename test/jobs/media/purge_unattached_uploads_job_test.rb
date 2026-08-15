require "test_helper"

module Media
  class PurgeUnattachedUploadsJobTest < ActiveJob::TestCase
    def blob(contents)
      ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new(contents),
        filename: "#{contents}.bin",
        content_type: "application/octet-stream"
      )
    end

    test "purges abandoned unattached uploads older than the grace period" do
      stale = blob("stale")
      stale.update_column(:created_at, 2.days.ago)
      in_flight = blob("in_flight") # unattached but recent — still being completed

      brand = Brand.create!(slug: "hookus", name: "HookUs")
      user = User.create!
      membership = BrandMembership.create!(brand:, user:)
      profile = Profile.create!(
        brand:, user:, brand_membership: membership,
        display_name: "Ada", birthdate: 25.years.ago.to_date, gender: "woman"
      )
      photo = ProfilePhoto.new(brand:, user:, profile:)
      photo.image.attach(io: StringIO.new("attached"), filename: "a.png", content_type: "image/png")
      photo.save!
      attached = photo.image.blob
      attached.update_column(:created_at, 2.days.ago)

      perform_enqueued_jobs do
        PurgeUnattachedUploadsJob.perform_now
      end

      assert_nil ActiveStorage::Blob.find_by(id: stale.id), "stale unattached blob should be purged"
      assert ActiveStorage::Blob.exists?(in_flight.id), "recent in-flight upload must be preserved"
      assert ActiveStorage::Blob.exists?(attached.id), "attached blob must never be purged"
    end
  end
end
