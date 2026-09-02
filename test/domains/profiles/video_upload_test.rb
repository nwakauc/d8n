require "test_helper"

module Profiles
  class VideoUploadTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    setup do
      ActiveStorage::Current.url_options = { host: "http://test.local" }
      @brand = Brand.create!(slug: "date9ja", name: "Date9ja")
      Profiles::Date9jaProfileCatalog.install!(brand: @brand)
      @user = User.create!
      @membership = BrandMembership.create!(brand: @brand, user: @user)
      @profile = Profile.create!(
        brand: @brand, user: @user, brand_membership: @membership,
        display_name: "Ada", birthdate: 26.years.ago.to_date, gender: "woman"
      )
      @bytes = build_test_mp4_bytes(codec: "avc1", duration_units: 5000, timescale: 1000) # 5s
    end

    teardown { ActiveStorage::Current.reset }

    def intent(content_type: "video/mp4", byte_size: nil)
      VideoUpload.create_intent(
        user: @user, brand: @brand, filename: "clip.mp4",
        byte_size: byte_size || @bytes.bytesize,
        checksum: Digest::MD5.base64digest(@bytes), content_type:
      )
    end

    def upload_bytes!(signed_id, bytes: @bytes)
      blob = ActiveStorage::Blob.find_signed!(signed_id)
      blob.service.upload(blob.key, StringIO.new(bytes), checksum: blob.checksum)
      signed_id
    end

    test "create_intent returns a brand-scoped presigned upload with the brand's limits" do
      result = intent

      assert result[:signed_id].present?
      assert result[:url].present?
      assert_equal 50.megabytes, result[:byte_size_limit]
      assert_equal 60, result[:max_duration_seconds]
      assert_equal %w[video/mp4 video/quicktime], result[:allowed_content_types]
      assert_not_includes result[:allowed_content_types], "video/webm"

      blob = ActiveStorage::Blob.find_signed!(result[:signed_id])
      assert_match %r{brands/date9ja/users/#{@user.id}/profiles/#{@profile.public_id}/videos/}, blob.key
    end

    test "create_intent rejects an unsupported content type and an oversized declared size" do
      assert_raises(VideoUpload::InvalidContentType) { intent(content_type: "video/x-msvideo") }
      assert_raises(VideoUpload::InvalidSize) { intent(byte_size: 51.megabytes) }
    end

    test "attach! verifies the real object, creates the pending video, and enqueues processing" do
      signed_id = upload_bytes!(intent[:signed_id])

      video = nil
      assert_enqueued_with(job: Media::ProcessProfileVideoJob) do
        video = VideoUpload.attach!(user: @user, brand: @brand, signed_id:)
      end

      assert video.persisted?
      assert video.pending_review?
      assert_equal :visible, video.visibility.to_sym
      # Duration + structural validation are the async job's job now.
      assert_nil video.duration_seconds
      assert video.processing_pending?
      assert video.video.attached?
      assert_equal @profile, video.profile
    end

    test "attach! reconciles the blob to the verified ISO-BMFF content type" do
      signed_id = upload_bytes!(intent[:signed_id])
      video = VideoUpload.attach!(user: @user, brand: @brand, signed_id:)

      assert_includes ProfileVideo::ALLOWED_CONTENT_TYPES, video.video.blob.content_type
      assert_equal @bytes.bytesize, video.video.blob.byte_size
    end

    test "attach! rejects a renamed non-video object" do
      bogus = "not a video at all, just plain text".b
      signed_id = VideoUpload.create_intent(
        user: @user, brand: @brand, filename: "fake.mp4", byte_size: bogus.bytesize,
        checksum: Digest::MD5.base64digest(bogus), content_type: "video/mp4"
      )[:signed_id]
      upload_bytes!(signed_id, bytes: bogus)

      assert_raises(VideoUpload::InvalidObject) do
        VideoUpload.attach!(user: @user, brand: @brand, signed_id:)
      end
    end

    test "attach! refuses a second video while one already exists" do
      VideoUpload.attach!(user: @user, brand: @brand, signed_id: upload_bytes!(intent[:signed_id]))

      second = upload_bytes!(intent[:signed_id])
      assert_raises(VideoUpload::AlreadyAttached) do
        VideoUpload.attach!(user: @user, brand: @brand, signed_id: second)
      end
    end

    test "a brand without profile video configured fails closed" do
      other = Brand.create!(slug: "hookus", name: "HookUs")
      Profiles::HookusProfileCatalog.install!(brand: other)
      user = User.create!
      BrandMembership.create!(brand: other, user:)
      Profile.create!(
        brand: other, user:, brand_membership: BrandMembership.find_by(brand: other, user:),
        display_name: "H", birthdate: 30.years.ago.to_date, gender: "man"
      )

      assert_raises(VideoUpload::NotConfigured) do
        VideoUpload.create_intent(
          user:, brand: other, filename: "c.mp4", byte_size: 100,
          checksum: Digest::MD5.base64digest("x"), content_type: "video/mp4"
        )
      end
    end
  end
end
