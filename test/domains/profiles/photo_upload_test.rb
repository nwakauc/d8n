require "test_helper"

module Profiles
  class PhotoUploadTest < ActiveSupport::TestCase
    setup do
      # The Disk service (dev/test) builds a routed direct-upload URL that needs
      # a host; R2 presigns without one. Supply a host so create_intent works.
      ActiveStorage::Current.url_options = { host: "http://test.local" }
    end

    teardown { ActiveStorage::Current.reset }

    test "detects supported image signatures from the leading bytes" do
      assert_equal "image/jpeg", PhotoUpload.detect_image_type("\xFF\xD8\xFF\xE0 rest".b)
      assert_equal "image/png", PhotoUpload.detect_image_type("\x89PNG\r\n\x1A\n rest".b)
      assert_equal "image/webp", PhotoUpload.detect_image_type("RIFF\x00\x00\x00\x00WEBPVP8 ".b)
    end

    test "rejects non-image and truncated signatures" do
      assert_nil PhotoUpload.detect_image_type("plain text")
      assert_nil PhotoUpload.detect_image_type("GIF89a".b)
      assert_nil PhotoUpload.detect_image_type("RIFF".b) # too short for WEBP marker
      assert_nil PhotoUpload.detect_image_type("")
      assert_nil PhotoUpload.detect_image_type(nil)
    end

    test "constants mirror the ProfilePhoto policy" do
      assert_equal ProfilePhoto::MAX_FILE_SIZE, PhotoUpload::MAX_FILE_SIZE
      assert_equal ProfilePhoto::ALLOWED_CONTENT_TYPES, PhotoUpload::ALLOWED_CONTENT_TYPES
    end

    test "attach applies the HookUs immediate-visibility policy" do
      brand, user = brand_with_profile("hookus")

      photo = attach_png(brand:, user:)

      assert_equal "visible", photo.visibility
      assert_equal "pending_review", photo.status
    end

    test "attach keeps a brand without an explicit photo policy moderate-first (hidden)" do
      # date9ja, hookus and dateza all now use immediate visibility via their
      # brand contracts; a brand with no registered contract fails closed to
      # moderate-first (see Media::PhotoPolicy).
      brand, user = brand_with_profile("unregistered-brand")

      photo = attach_png(brand:, user:)

      assert_equal "hidden", photo.visibility
      assert_equal "pending_review", photo.status
    end

    test "attach stores the object under a server-allocated brand-scoped key" do
      brand, user = brand_with_profile("hookus")

      photo = attach_png(brand:, user:)

      assert_match %r{\Abrands/hookus/users/#{user.id}/profiles/[0-9a-f-]{36}/photos/[0-9a-f-]{36}/original\.png\z},
        photo.image.blob.key
    end

    test "upload intent persists the brand-resolved service for signing and later lifecycle operations" do
      brand, user = brand_with_profile("hookus")
      resolver = Object.new
      resolver.define_singleton_method(:service_name) { |brand:| "brand_test" }

      intent = PhotoUpload.create_intent(
        user:, brand:, filename: "photo.png",
        byte_size: png_bytes.bytesize, checksum: Digest::MD5.base64digest(png_bytes),
        content_type: "image/png", storage_resolver: resolver
      )
      blob = ActiveStorage::Blob.find_signed!(intent.fetch(:signed_id))

      assert_equal "brand_test", blob.service_name
      assert_equal ActiveStorage::Blob.services.fetch(:brand_test), blob.service
    end

    private

    def brand_with_profile(slug)
      brand = Brand.create!(slug:, name: slug)
      user = User.create!
      membership = BrandMembership.create!(brand:, user:)
      Profile.create!(
        brand:, user:, brand_membership: membership,
        display_name: "Ada", birthdate: 25.years.ago.to_date, gender: "woman"
      )
      [ brand, user ]
    end

    def attach_png(brand:, user:)
      intent = PhotoUpload.create_intent(
        user:, brand:, filename: "photo.png",
        byte_size: png_bytes.bytesize, checksum: Digest::MD5.base64digest(png_bytes),
        content_type: "image/png"
      )
      blob = ActiveStorage::Blob.find_signed!(intent.fetch(:signed_id))
      blob.service.upload(blob.key, StringIO.new(png_bytes), checksum: blob.checksum)
      PhotoUpload.attach!(user:, brand:, signed_id: intent.fetch(:signed_id))
    end

    def png_bytes
      @png_bytes ||= Base64.decode64(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
      ).b
    end
  end
end
