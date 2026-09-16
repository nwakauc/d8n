require "test_helper"

class Api::V1::ProfileVideosControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @brand = Brands::Date9jaInstaller.call(hosts: [ "date9ja.test" ])
    @user = User.create!
    @membership = BrandMembership.create!(brand: @brand, user: @user)
    @profile = Profile.create!(
      brand: @brand, user: @user, brand_membership: @membership,
      display_name: "Ada", birthdate: 26.years.ago.to_date, gender: "woman"
    )
    @token, = Session.issue!(brand: @brand, user: @user)
    host! "date9ja.test"
    @bytes = build_test_mp4_bytes(codec: "avc1", duration_units: 4000, timescale: 1000)
  end

  def auth = { "Authorization" => "Bearer #{@token}" }

  test "requires authentication" do
    get "/api/v1/profile/video"
    assert_response :unauthorized
  end

  test "show returns null when there is no video" do
    get "/api/v1/profile/video", headers: auth
    assert_response :success
    assert_nil JSON.parse(response.body).fetch("video")
  end

  test "full upload lifecycle: intent, attach, show, delete" do
    post "/api/v1/profile/video/uploads", headers: auth, params: {
      content_type: "video/mp4", byte_size: @bytes.bytesize, checksum: Digest::MD5.base64digest(@bytes)
    }
    assert_response :created
    upload = JSON.parse(response.body).fetch("upload")
    assert_equal 60, upload.fetch("max_duration_seconds")

    blob = ActiveStorage::Blob.find_signed!(upload.fetch("signed_id"))
    blob.service.upload(blob.key, StringIO.new(@bytes), checksum: blob.checksum)

    assert_enqueued_with(job: Media::ProcessProfileVideoJob) do
      post "/api/v1/profile/video", headers: auth, params: { signed_id: upload.fetch("signed_id") }
    end
    assert_response :created
    body = JSON.parse(response.body).fetch("video")
    assert_equal "pending_review", body.fetch("status")
    assert_equal "pending", body.fetch("processing_state")
    assert_nil body.fetch("duration_seconds") # set by the async job

    get "/api/v1/profile/video", headers: auth
    assert_equal "visible", JSON.parse(response.body).dig("video", "visibility")

    delete "/api/v1/profile/video", headers: auth
    assert_response :no_content
    assert_not ProfileVideo.kept.exists?(profile: @profile)
  end

  test "rejects a renamed non-video upload synchronously" do
    bogus = "definitely not a video".b
    post "/api/v1/profile/video/uploads", headers: auth, params: {
      content_type: "video/mp4", byte_size: bogus.bytesize, checksum: Digest::MD5.base64digest(bogus)
    }
    signed_id = JSON.parse(response.body).dig("upload", "signed_id")
    blob = ActiveStorage::Blob.find_signed!(signed_id)
    blob.service.upload(blob.key, StringIO.new(bogus), checksum: blob.checksum)

    post "/api/v1/profile/video", headers: auth, params: { signed_id: }
    assert_response :unprocessable_entity
    assert_equal "invalid_video", JSON.parse(response.body).fetch("error")
  end

  test "delete with no video is a 404" do
    delete "/api/v1/profile/video", headers: auth
    assert_response :not_found
  end

  test "a brand whose contract does not enable profile video returns 404" do
    hookus = Brands::HookusInstaller.call(hosts: [ "hookus.test" ])
    user = User.create!
    BrandMembership.create!(brand: hookus, user:)
    Profile.create!(
      brand: hookus, user:, brand_membership: BrandMembership.find_by(brand: hookus, user:),
      display_name: "H", birthdate: 30.years.ago.to_date, gender: "man"
    )
    token, = Session.issue!(brand: hookus, user:)
    host! "hookus.test"

    get "/api/v1/profile/video", headers: { "Authorization" => "Bearer #{token}" }
    assert_response :not_found
  end
end
