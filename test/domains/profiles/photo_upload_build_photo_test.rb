# frozen_string_literal: true

require "test_helper"
require "vips"

module Profiles
  class PhotoUploadBuildPhotoTest < ActiveSupport::TestCase
    setup do
      @brand = Brand.create!(slug: "date9ja", name: "Date9ja", status: :active,
        auth_methods: %w[email_password])
      @user = User.create!
      @membership = BrandMembership.create!(brand: @brand, user: @user)
      @profile = Profile.create!(brand: @brand, user: @user, brand_membership: @membership,
        display_name: "Ada", birthdate: 25.years.ago.to_date, gender: "woman")
    end

    def blob(seed: 1)
      bytes = Vips::Image.black(60, 40).add([ 30 + seed ]).cast("uchar").write_to_buffer(".jpg")
      key = "migrations/media/v3/date9ja/profile_photo_original/#{SecureRandom.uuid}/original.jpg"
      ActiveStorage::Blob.create_and_upload!(io: StringIO.new(bytes), key:, filename: "original.jpg",
        content_type: "image/jpeg", service_name: ActiveStorage::Blob.service.name)
    end

    test "builds a ProfilePhoto with explicit source-derived position/status/visibility" do
      photo = PhotoUpload.build_photo!(
        profile: @profile, user: @user, brand: @brand, blob: blob,
        position: 0, status: :approved, visibility: :visible
      )
      assert photo.persisted?
      assert photo.approved?
      assert photo.visible?
      assert_equal 0, photo.position
      assert photo.image.attached?
    end

    test "enforces the brand photo capacity invariant" do
      6.times { |i| PhotoUpload.build_photo!(profile: @profile, user: @user, brand: @brand, blob: blob(seed: i), status: :approved, visibility: :visible) }
      assert_raises(PhotoUpload::LimitReached) do
        PhotoUpload.build_photo!(profile: @profile, user: @user, brand: @brand, blob: blob(seed: 9), status: :approved, visibility: :visible)
      end
    end

    test "enforces owner/profile/brand scope" do
      other = User.create!
      assert_raises(ActiveRecord::RecordInvalid) do
        PhotoUpload.build_photo!(profile: @profile, user: other, brand: @brand, blob: blob, status: :approved, visibility: :visible)
      end
    end

    test "rejects a blob already attached elsewhere" do
      b = blob
      PhotoUpload.build_photo!(profile: @profile, user: @user, brand: @brand, blob: b, status: :approved, visibility: :visible)
      assert_raises(PhotoUpload::AlreadyAttached) do
        PhotoUpload.build_photo!(profile: @profile, user: @user, brand: @brand, blob: b, status: :approved, visibility: :visible)
      end
    end
  end
end
