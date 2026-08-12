require "test_helper"

class Api::V1::ProfilePhotosControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  teardown do
    clear_enqueued_jobs
    clear_performed_jobs
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

  test "requires authentication" do
    get "/api/v1/profile/photos"

    assert_response :unauthorized
  end

  test "lists current brand profile photos" do
    photo = create_photo

    get "/api/v1/profile/photos", headers: bearer_headers(@token)

    assert_response :success
    photos = JSON.parse(response.body).fetch("photos")
    assert_equal 1, photos.size
    assert_equal photo.id, photos.first.fetch("id")
    assert_equal "image/png", photos.first.fetch("image").fetch("content_type")
  end

  test "uploads a current profile photo" do
    assert_difference -> { ProfilePhoto.count }, 1 do
      post "/api/v1/profile/photos",
        headers: bearer_headers(@token),
        params: { image: uploaded_image }
    end

    assert_response :created
    photo = ProfilePhoto.last
    response_body = JSON.parse(response.body).fetch("photo")

    assert_equal @brand, photo.brand
    assert_equal @user, photo.user
    assert_equal @profile, photo.profile
    assert photo.image.attached?
    assert_equal "pending_review", response_body.fetch("status")
    assert_equal "hidden", response_body.fetch("visibility")
    assert_equal "/rails/active_storage/blobs", response_body.fetch("image").fetch("url")[0, 27]
  end

  test "rejects uploads before a profile exists" do
    @profile.destroy!

    post "/api/v1/profile/photos",
      headers: bearer_headers(@token),
      params: { image: uploaded_image }

    assert_response :forbidden
    assert_equal({ "error" => "profile_required" }, JSON.parse(response.body))
  end

  test "rejects uploads without an image" do
    post "/api/v1/profile/photos", headers: bearer_headers(@token)

    assert_response :unprocessable_entity
    assert_equal({ "error" => "image_required" }, JSON.parse(response.body))
  end

  test "soft deletes current brand profile photo" do
    photo = create_photo

    assert_enqueued_with(job: ActiveStorage::PurgeJob) do
      delete "/api/v1/profile/photos/#{photo.id}", headers: bearer_headers(@token)
    end

    assert_response :success
    photo.reload
    assert photo.deleted_at.present?
    assert photo.hidden?
    assert JSON.parse(response.body).fetch("photo").fetch("deleted_at").present?
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
    other_photo = create_photo(brand: other_brand, profile: other_profile)

    delete "/api/v1/profile/photos/#{other_photo.id}", headers: bearer_headers(@token)

    assert_response :not_found
    assert_nil other_photo.reload.deleted_at
  end

  private

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end

  def uploaded_image
    fixture_file_upload("profile_photo.png", "image/png")
  end

  def create_photo(brand: @brand, profile: @profile)
    photo = ProfilePhoto.new(brand:, user: @user, profile:)
    photo.image.attach(uploaded_image)
    photo.save!
    photo
  end
end
