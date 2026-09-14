require "test_helper"

class Api::V1::RealmeVerificationsControllerTest < ActionDispatch::IntegrationTest
  teardown { ActiveStorage::Blob.all.each { |blob| blob.purge rescue nil } }

  setup do
    @brand = Brand.create!(slug: "date9ja", name: "Date9ja")
    BrandDomain.create!(brand: @brand, host: "date9ja.test")
    @user = User.create!
    @membership = BrandMembership.create!(brand: @brand, user: @user)
    @profile = Profile.create!(
      brand: @brand, user: @user, brand_membership: @membership,
      display_name: "Ada", birthdate: 25.years.ago.to_date, gender: "woman"
    )
    @token, = Session.issue!(brand: @brand, user: @user)
    host! "date9ja.test"
  end

  test "upload intent requires authentication" do
    post "/api/v1/realme_verifications/uploads", params: valid_intent_params

    assert_response :unauthorized
  end

  test "upload intent returns a short-lived direct upload authorization" do
    assert_difference -> { ActiveStorage::Blob.count }, 1 do
      post "/api/v1/realme_verifications/uploads", headers: bearer_headers(@token), params: valid_intent_params
    end

    assert_response :created
    upload = JSON.parse(response.body).fetch("upload")
    assert upload.fetch("signed_id").present?
    assert upload.fetch("url").present?
  end

  test "rejects an unsupported check_type" do
    post "/api/v1/realme_verifications/uploads", headers: bearer_headers(@token),
      params: valid_intent_params(check_type: "fingerprint")

    assert_response :unprocessable_entity
    assert_equal "unsupported_check_type", JSON.parse(response.body).fetch("error")
  end

  test "completes an upload into a pending verification assertion" do
    bytes = build_test_jpeg_bytes
    signed_id = create_intent_signed_id(bytes)
    complete_upload(bytes, signed_id:)

    assert_difference -> { VerificationAssertion.count }, 1 do
      post "/api/v1/realme_verifications", headers: bearer_headers(@token),
        params: { check_type: "selfie", signed_id: }
    end

    assert_response :created
    body = JSON.parse(response.body).fetch("assertion")
    assert_equal "selfie", body.fetch("check_type")
    assert_equal "pending", body.fetch("status")
  end

  test "refuses a second submission while one is already pending" do
    VerificationAssertion.create!(
      brand: @brand, user: @user, source_type: "member_submission", source_id: "existing",
      check_type: "selfie", status: "pending"
    )

    post "/api/v1/realme_verifications/uploads", headers: bearer_headers(@token), params: valid_intent_params

    assert_response :unprocessable_entity
    assert_equal "verification_already_pending", JSON.parse(response.body).fetch("error")
  end

  private

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end

  def valid_intent_params(check_type: "selfie", content_type: "image/jpeg", byte_size: 1024)
    { check_type:, filename: "s.jpg", byte_size:, checksum: "deadbeef", content_type: }
  end

  def create_intent_signed_id(bytes, check_type: "selfie", content_type: "image/jpeg")
    post "/api/v1/realme_verifications/uploads", headers: bearer_headers(@token),
      params: valid_intent_params(check_type:, content_type:, byte_size: bytes.bytesize).merge(
        checksum: Digest::MD5.base64digest(bytes)
      )
    JSON.parse(response.body).fetch("upload").fetch("signed_id")
  end

  def complete_upload(bytes, signed_id:)
    blob = ActiveStorage::Blob.find_signed(signed_id)
    blob.service.upload(blob.key, StringIO.new(bytes), checksum: blob.checksum)
  end
end
