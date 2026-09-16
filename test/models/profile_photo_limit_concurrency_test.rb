require "test_helper"

class ProfilePhotoLimitConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  test "concurrent attachments cannot exceed the brand photo maximum" do
    ActiveStorage::Current.url_options = { host: "http://test.local" }
    brand = Brand.create!(slug: "hookus", name: "HookUs")
    user = User.create!
    membership = BrandMembership.create!(brand:, user:)
    profile = Profile.create!(brand:, user:, brand_membership: membership)
    5.times { |position| create_photo(profile:, position:) }
    signed_ids = 2.times.map { completed_upload(user:, brand:) }
    outcomes = Queue.new
    start = Queue.new

    threads = signed_ids.map do |signed_id|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          start.pop
          outcomes << Profiles::PhotoUpload.attach!(user:, brand:, signed_id:)
        rescue StandardError => e
          outcomes << e
        end
      end
    end
    2.times { start << true }
    threads.each(&:join)
    results = 2.times.map { outcomes.pop }

    assert_equal 6, profile.profile_photos.kept.count
    assert_equal 1, results.count { |result| result.is_a?(ProfilePhoto) }
    assert_equal 1, results.count { |result| result.is_a?(Profiles::PhotoUpload::LimitReached) }
    assert_equal (0...6).to_a, profile.profile_photos.kept.ordered.pluck(:position)
  ensure
    ActiveStorage::Current.reset
    if brand
      photo_ids = ProfilePhoto.where(brand:).pluck(:id)
      blob_ids = ActiveStorage::Attachment.where(record_type: "ProfilePhoto", record_id: photo_ids).pluck(:blob_id)
      ActiveStorage::Attachment.where(record_type: "ProfilePhoto", record_id: photo_ids).delete_all
      ProfilePhoto.where(brand:).delete_all
      AnalyticsEvent.where(brand:).delete_all
      Profile.where(brand:).delete_all
      BrandMembership.where(brand:).delete_all
      ActiveStorage::Blob.where(id: blob_ids).find_each(&:purge)
      ActiveStorage::Blob.where(id: signed_ids.filter_map { |id| ActiveStorage::Blob.find_signed(id)&.id }).find_each(&:purge) if signed_ids
      user&.destroy!
      brand.destroy!
    end
  end

  private

  def create_photo(profile:, position:)
    photo = ProfilePhoto.new(brand: profile.brand, user: profile.user, profile:, position:)
    photo.image.attach(
      io: StringIO.new(png_bytes), filename: "profile_photo.png", content_type: "image/png"
    )
    photo.save!
  end

  def completed_upload(user:, brand:)
    intent = Profiles::PhotoUpload.create_intent(
      user:, brand:, filename: "photo.png", byte_size: png_bytes.bytesize,
      checksum: Digest::MD5.base64digest(png_bytes), content_type: "image/png"
    )
    blob = ActiveStorage::Blob.find_signed!(intent.fetch(:signed_id))
    blob.service.upload(blob.key, StringIO.new(png_bytes), checksum: blob.checksum)
    intent.fetch(:signed_id)
  end

  def png_bytes
    @png_bytes ||= Base64.decode64(
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
    ).b
  end
end
