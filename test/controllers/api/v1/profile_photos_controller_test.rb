require "test_helper"

class Api::V1::ProfilePhotosControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  teardown do
    clear_enqueued_jobs
    clear_performed_jobs
    ActiveStorage::Blob.all.each { |blob| blob.purge rescue nil }
  end

  setup do
    @brand = Brand.create!(slug: "hookus", name: "HookUs")
    BrandDomain.create!(brand: @brand, host: "hookus.test")
    @user = User.create!
    @membership = BrandMembership.create!(brand: @brand, user: @user)
    @profile = Profile.create!(
      brand: @brand,
      user: @user,
      brand_membership: @membership,
      display_name: "Ada",
      birthdate: 25.years.ago.to_date,
      gender: "woman"
    )
    @token, = Session.issue!(brand: @brand, user: @user)
    host! "hookus.test"
  end

  # --- gating / auth ---------------------------------------------------------

  test "index requires authentication" do
    get "/api/v1/profile/photos"

    assert_response :unauthorized
  end

  test "upload intent requires authentication" do
    post "/api/v1/profile/photos/uploads", params: valid_intent_params

    assert_response :unauthorized
  end

  test "endpoints are closed when the photo API is disabled" do
    with_photos_disabled do
      post "/api/v1/profile/photos/uploads", headers: bearer_headers(@token), params: valid_intent_params
      assert_response :not_found

      post "/api/v1/profile/photos", headers: bearer_headers(@token), params: { signed_id: "x" }
      assert_response :not_found
    end
  end

  # --- upload intent (control plane) ----------------------------------------

  test "upload intent returns a short-lived direct upload authorization" do
    assert_difference -> { ActiveStorage::Blob.count }, 1 do
      post "/api/v1/profile/photos/uploads", headers: bearer_headers(@token), params: valid_intent_params
    end

    assert_response :created
    upload = JSON.parse(response.body).fetch("upload")
    assert upload.fetch("signed_id").present?
    assert upload.fetch("url").present?
    assert_kind_of Hash, upload.fetch("headers")
    assert_operator upload.fetch("expires_in"), :>, 0
    assert_equal ProfilePhoto::MAX_FILE_SIZE, upload.fetch("byte_size_limit")
    assert_equal ProfilePhoto::ALLOWED_CONTENT_TYPES, upload.fetch("allowed_content_types")
    # The client is never handed the object key or any credential.
    assert_no_match(/access_key|secret/i, response.body)
  end

  test "upload intent allocates a server-controlled, brand/profile-scoped, PII-free key" do
    post "/api/v1/profile/photos/uploads", headers: bearer_headers(@token), params: valid_intent_params

    assert_response :created
    blob = ActiveStorage::Blob.last
    assert_equal(
      "brands/#{@brand.slug}/users/#{@user.id}/profiles/#{@profile.public_id}",
      blob.key.split("/photos/").first
    )
    assert_match %r{\Abrands/hookus/users/\d+/profiles/[0-9a-f-]{36}/photos/[0-9a-f-]{36}/original\.png\z}, blob.key
    # The client never sees or chooses the key.
    assert_no_match(/#{Regexp.escape(blob.key)}/, response.body)
    # No PII (declared filename, and there is no email/name in scope) leaks in.
    assert_not_includes blob.key, "photo.png"
  end

  test "upload intent rejects an unsupported content type" do
    post "/api/v1/profile/photos/uploads",
      headers: bearer_headers(@token),
      params: valid_intent_params(content_type: "image/gif")

    assert_response :unprocessable_entity
    assert_equal "unsupported_content_type", JSON.parse(response.body).fetch("error")
  end

  test "upload intent rejects an oversized declared byte size" do
    post "/api/v1/profile/photos/uploads",
      headers: bearer_headers(@token),
      params: valid_intent_params(byte_size: ProfilePhoto::MAX_FILE_SIZE + 1)

    assert_response :unprocessable_entity
    assert_equal "invalid_byte_size", JSON.parse(response.body).fetch("error")
  end

  test "upload intent requires a checksum" do
    params = valid_intent_params
    params.delete(:checksum)

    post "/api/v1/profile/photos/uploads", headers: bearer_headers(@token), params: params

    assert_response :unprocessable_entity
    assert_equal "upload_parameters_required", JSON.parse(response.body).fetch("error")
  end

  test "upload intent is forbidden without a profile" do
    @profile.destroy!

    assert_no_difference -> { ActiveStorage::Blob.count } do
      post "/api/v1/profile/photos/uploads", headers: bearer_headers(@token), params: valid_intent_params
    end

    assert_response :forbidden
    assert_equal "profile_required", JSON.parse(response.body).fetch("error")
  end

  # --- attach (data plane completion) ---------------------------------------

  test "attaches a completed upload to the current profile" do
    signed_id = complete_upload(png_bytes)

    assert_difference -> { ProfilePhoto.count }, 1 do
      post "/api/v1/profile/photos", headers: bearer_headers(@token), params: { signed_id: signed_id }
    end

    assert_response :created
    body = JSON.parse(response.body).fetch("photo")
    photo = ProfilePhoto.last
    assert_equal @brand, photo.brand
    assert_equal @user, photo.user
    assert_equal @profile, photo.profile
    assert photo.image.attached?
    # HookUs policy: an ordinary valid photo is usable immediately (visible),
    # still pending an asynchronous moderation pass.
    assert_equal "pending_review", body.fetch("status")
    assert_equal "visible", body.fetch("visibility")
    assert_equal @profile.public_id, body.fetch("profile_id")
    assert_equal "image/png", body.fetch("image").fetch("content_type")
    assert body.fetch("image").fetch("url").present?
    assert_operator body.fetch("image").fetch("url_expires_in"), :>, 0
    # Delivery is not a permanent generic Active Storage blob path.
    assert_not_includes body.fetch("image").fetch("url"), "/rails/active_storage/blobs"
  end

  test "attach requires a signed id" do
    post "/api/v1/profile/photos", headers: bearer_headers(@token), params: {}

    assert_response :unprocessable_entity
    assert_equal "signed_id_required", JSON.parse(response.body).fetch("error")
  end

  test "attach rejects an invalid signed id" do
    post "/api/v1/profile/photos", headers: bearer_headers(@token), params: { signed_id: "not-a-real-id" }

    assert_response :unprocessable_entity
    assert_equal "invalid_upload", JSON.parse(response.body).fetch("error")
  end

  test "attach rejects a signed id whose object was never uploaded" do
    signed_id = create_intent_signed_id(png_bytes) # intent only, no direct PUT

    assert_no_difference -> { ProfilePhoto.count } do
      post "/api/v1/profile/photos", headers: bearer_headers(@token), params: { signed_id: signed_id }
    end

    assert_response :unprocessable_entity
    assert_equal "upload_not_found", JSON.parse(response.body).fetch("error")
  end

  test "attach rejects an object that is not a supported image" do
    signed_id = complete_upload("this is not an image", content_type: "image/png")

    assert_no_difference -> { ProfilePhoto.count } do
      post "/api/v1/profile/photos", headers: bearer_headers(@token), params: { signed_id: signed_id }
    end

    assert_response :unprocessable_entity
    assert_equal "invalid_image", JSON.parse(response.body).fetch("error")
  end

  test "attach rejects a reused signed id" do
    signed_id = complete_upload(png_bytes)
    post "/api/v1/profile/photos", headers: bearer_headers(@token), params: { signed_id: signed_id }
    assert_response :created

    post "/api/v1/profile/photos", headers: bearer_headers(@token), params: { signed_id: signed_id }
    assert_response :unprocessable_entity
    assert_equal "upload_already_used", JSON.parse(response.body).fetch("error")
  end

  test "attach is forbidden without a profile" do
    signed_id = complete_upload(png_bytes)
    @profile.destroy!

    post "/api/v1/profile/photos", headers: bearer_headers(@token), params: { signed_id: signed_id }

    assert_response :forbidden
    assert_equal "profile_required", JSON.parse(response.body).fetch("error")
  end

  # --- retrieval / deletion --------------------------------------------------

  test "lists current brand photos with signed retrieval urls" do
    photo = create_attached_photo

    get "/api/v1/profile/photos", headers: bearer_headers(@token)

    assert_response :success
    photos = JSON.parse(response.body).fetch("photos")
    assert_equal 1, photos.size
    image = photos.first.fetch("image")
    assert_equal photo.id, photos.first.fetch("id")
    assert_equal "image/png", image.fetch("content_type")
    assert image.fetch("url").present?
    assert_operator image.fetch("url_expires_in"), :>, 0
  end

  test "soft deletes a current brand photo and enqueues purge" do
    photo = create_attached_photo

    assert_enqueued_with(job: ActiveStorage::PurgeJob) do
      delete "/api/v1/profile/photos/#{photo.id}", headers: bearer_headers(@token)
    end

    assert_response :success
    photo.reload
    assert photo.deleted_at.present?
    assert photo.hidden?
  end

  test "does not delete another brand photo for the same user" do
    other_brand = Brand.create!(slug: "date9ja", name: "Date9ja")
    other_membership = BrandMembership.create!(brand: other_brand, user: @user)
    other_profile = Profile.create!(
      brand: other_brand,
      user: @user,
      brand_membership: other_membership,
      display_name: "Date9ja Ada",
      birthdate: 25.years.ago.to_date,
      gender: "woman"
    )
    other_photo = build_attached_photo(brand: other_brand, profile: other_profile)

    delete "/api/v1/profile/photos/#{other_photo.id}", headers: bearer_headers(@token)

    assert_response :not_found
    assert_nil other_photo.reload.deleted_at
  end

  private

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end

  # A real 1x1 PNG. The checked-in profile_photo.png fixture is a text
  # placeholder, so it cannot exercise the server-side image verification.
  def png_bytes
    @png_bytes ||= Base64.decode64(
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
    ).b
  end

  def valid_intent_params(content_type: "image/png", byte_size: nil, bytes: nil)
    bytes ||= png_bytes
    {
      content_type: content_type,
      byte_size: byte_size || bytes.bytesize,
      checksum: Digest::MD5.base64digest(bytes),
      filename: "photo.png"
    }
  end

  # Runs the control-plane intent and returns the signed id, without uploading.
  def create_intent_signed_id(bytes, content_type: "image/png")
    post "/api/v1/profile/photos/uploads",
      headers: bearer_headers(@token),
      params: valid_intent_params(content_type: content_type, bytes: bytes)
    JSON.parse(response.body).fetch("upload").fetch("signed_id")
  end

  # Simulates the client's direct PUT to R2 by writing the bytes to the
  # configured storage service under the D8N-allocated key.
  def complete_upload(bytes, content_type: "image/png")
    signed_id = create_intent_signed_id(bytes, content_type: content_type)
    blob = ActiveStorage::Blob.find_signed!(signed_id)
    blob.service.upload(blob.key, StringIO.new(bytes), checksum: blob.checksum)
    signed_id
  end

  def create_attached_photo(brand: @brand, profile: @profile)
    build_attached_photo(brand: brand, profile: profile)
  end

  def build_attached_photo(brand:, profile:)
    photo = ProfilePhoto.new(brand: brand, user: @user, profile: profile)
    photo.image.attach(
      io: StringIO.new(png_bytes),
      filename: "profile_photo.png",
      content_type: "image/png"
    )
    photo.save!
    photo
  end

  def with_photos_disabled
    previous = Rails.configuration.x.profile_photos_enabled
    Rails.configuration.x.profile_photos_enabled = false
    yield
  ensure
    Rails.configuration.x.profile_photos_enabled = previous
  end
end
