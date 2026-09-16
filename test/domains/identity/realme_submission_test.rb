require "test_helper"

class Identity::RealmeSubmissionTest < ActiveSupport::TestCase
  teardown do
    ActiveStorage::Blob.all.each { |blob| blob.purge rescue nil }
    ActiveStorage::Current.reset
  end

  setup do
    # The Disk service (dev/test) builds a routed direct-upload URL that needs
    # a host; R2 presigns without one. Supply a host so create_intent works.
    ActiveStorage::Current.url_options = { host: "http://test.local" }
    @brand = Brand.create!(slug: "date9ja", name: "Date9ja")
    @user = User.create!
    @membership = BrandMembership.create!(brand: @brand, user: @user)
    @profile = Profile.create!(
      brand: @brand, user: @user, brand_membership: @membership,
      display_name: "Ada", birthdate: 25.years.ago.to_date, gender: "woman"
    )
  end

  test "requires an existing profile" do
    stray = User.create!

    assert_raises(Identity::RealmeSubmission::ProfileRequired) do
      Identity::RealmeSubmission.create_intent(
        user: stray, brand: @brand, check_type: "selfie",
        filename: "s.png", byte_size: 10, checksum: "x", content_type: "image/png"
      )
    end
  end

  test "rejects an unknown check_type" do
    assert_raises(Identity::RealmeSubmission::InvalidCheckType) do
      Identity::RealmeSubmission.create_intent(
        user: @user, brand: @brand, check_type: "fingerprint",
        filename: "f.png", byte_size: 10, checksum: "x", content_type: "image/png"
      )
    end
  end

  test "rejects a video content type for an image check" do
    assert_raises(Identity::RealmeSubmission::InvalidContentType) do
      Identity::RealmeSubmission.create_intent(
        user: @user, brand: @brand, check_type: "selfie",
        filename: "s.mp4", byte_size: 10, checksum: "x", content_type: "video/mp4"
      )
    end
  end

  test "issues a direct-upload intent and attach! creates a pending assertion with the evidence attached" do
    bytes = build_test_jpeg_bytes
    intent = Identity::RealmeSubmission.create_intent(
      user: @user, brand: @brand, check_type: "selfie",
      filename: "s.jpg", byte_size: bytes.bytesize, checksum: Digest::MD5.base64digest(bytes),
      content_type: "image/jpeg"
    )

    blob = ActiveStorage::Blob.find_signed(intent.fetch(:signed_id))
    blob.service.upload(blob.key, StringIO.new(bytes), checksum: blob.checksum)

    assertion = Identity::RealmeSubmission.attach!(
      user: @user, brand: @brand, check_type: "selfie", signed_id: intent.fetch(:signed_id)
    )

    assert_equal "pending", assertion.status
    assert_equal "selfie", assertion.check_type
    assert_equal "member_submission", assertion.source_type
    assert assertion.submitted_at.present?
    assert assertion.evidence.attached?
  end

  test "refuses a second submission for a check_type that already has a pending assertion" do
    VerificationAssertion.create!(
      brand: @brand, user: @user, source_type: "member_submission", source_id: "existing",
      check_type: "selfie", status: "pending"
    )

    assert_raises(Identity::RealmeSubmission::PendingSubmissionExists) do
      Identity::RealmeSubmission.create_intent(
        user: @user, brand: @brand, check_type: "selfie",
        filename: "s.jpg", byte_size: 10, checksum: "x", content_type: "image/jpeg"
      )
    end
  end

  test "allows resubmission after rejection" do
    VerificationAssertion.create!(
      brand: @brand, user: @user, source_type: "member_submission", source_id: "old",
      check_type: "selfie", status: "rejected"
    )

    bytes = build_test_jpeg_bytes
    intent = Identity::RealmeSubmission.create_intent(
      user: @user, brand: @brand, check_type: "selfie",
      filename: "s.jpg", byte_size: bytes.bytesize, checksum: Digest::MD5.base64digest(bytes),
      content_type: "image/jpeg"
    )
    blob = ActiveStorage::Blob.find_signed(intent.fetch(:signed_id))
    blob.service.upload(blob.key, StringIO.new(bytes), checksum: blob.checksum)

    assertion = Identity::RealmeSubmission.attach!(
      user: @user, brand: @brand, check_type: "selfie", signed_id: intent.fetch(:signed_id)
    )

    assert_equal "pending", assertion.status
    assert_equal 2, VerificationAssertion.where(brand: @brand, user: @user, check_type: "selfie").count
  end
end
