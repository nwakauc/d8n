# frozen_string_literal: true

require "test_helper"
require "vips"

module Media
  # The single authoritative display-derivative validation contract (review
  # Finding 1). Callers: ProcessProfilePhotoJob + Migration::MediaTransfer.
  class DisplayDerivativeTest < ActiveSupport::TestCase
    def jpeg = Vips::Image.black(60, 40).add([ 80 ]).cast("uchar").write_to_buffer(".jpg").b

    def ready_photo
      brand = Brand.create!(slug: "hookus", name: "HookUs")
      user = User.create!
      m = BrandMembership.create!(brand:, user:)
      profile = Profile.create!(brand:, user:, brand_membership: m, display_name: "A",
        birthdate: 25.years.ago.to_date, gender: "woman")
      okey = Media::ObjectKey.profile_photo_original(brand:, user:, profile:, content_type: "image/jpeg")
      raw = ActiveStorage::Blob.create_and_upload!(io: StringIO.new(jpeg), key: okey, filename: "original.jpg",
        content_type: "image/jpeg", service_name: ActiveStorage::Blob.service.name)
      photo = ProfilePhoto.new(brand:, user:, profile:)
      photo.image.attach(raw)
      photo.save!
      Media::ProcessProfilePhotoJob.perform_now(photo.id)
      [ photo.reload, Media::ObjectKey.profile_photo_display(okey) ]
    end

    def svc = ActiveStorage::Blob.service.name.to_s

    test "true only for the exact deterministic artifact with verified bytes" do
      photo, dkey = ready_photo
      assert DisplayDerivative.valid?(photo:, expected_display_key: dkey, expected_service: svc)
    end

    test "false for a wrong key, wrong service, blank inputs" do
      photo, dkey = ready_photo
      refute DisplayDerivative.valid?(photo:, expected_display_key: "#{dkey}x", expected_service: svc)
      refute DisplayDerivative.valid?(photo:, expected_display_key: dkey, expected_service: "brand_test")
      refute DisplayDerivative.valid?(photo:, expected_display_key: nil, expected_service: svc)
      refute DisplayDerivative.valid?(photo:, expected_display_key: dkey, expected_service: nil)
    end

    test "false when the remote object is missing or tampered or checksum drifts" do
      photo, dkey = ready_photo
      blob = photo.display_image.blob

      blob.service.delete(dkey)
      refute DisplayDerivative.valid?(photo:, expected_display_key: dkey, expected_service: svc)

      blob.service.upload(dkey, StringIO.new("not an image"))
      refute DisplayDerivative.valid?(photo:, expected_display_key: dkey, expected_service: svc)

      junk = SecureRandom.bytes(blob.byte_size)
      blob.service.upload(dkey, StringIO.new(junk)) # right size, wrong checksum/bytes
      refute DisplayDerivative.valid?(photo:, expected_display_key: dkey, expected_service: svc)
    end

    test "false when no display is attached" do
      photo, dkey = ready_photo
      photo.display_image.detach
      refute DisplayDerivative.valid?(photo: photo.reload, expected_display_key: dkey, expected_service: svc)
    end

    test "bounded_download fails closed past the ceiling" do
      photo, dkey = ready_photo
      stub = Object.new
      stub.define_singleton_method(:download) { |_k, &blk| blk.call("x" * (DisplayDerivative::BYTE_CEILING + 1)) }
      assert_raises(DisplayDerivative::RemoteTooLarge) { DisplayDerivative.bounded_download(stub, dkey) }
    end
  end
end
