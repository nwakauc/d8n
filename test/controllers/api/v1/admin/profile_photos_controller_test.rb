require "test_helper"

class Api::V1::Admin::ProfilePhotosControllerTest < ActionDispatch::IntegrationTest
  setup do
    @brand = Brand.create!(
      slug: "dateza", name: "DateZA",
      profile_requirements: { profile_fields: [], preference_fields: [], collections: %w[ photos ] }
    )
    BrandDomain.create!(brand: @brand, host: "dateza.test")
    @profile = create_profile(brand: @brand)
    @photo = create_ready_photo(profile: @profile, visibility: :hidden)
    @admin, @token = create_admin(brand: @brand)
    host! "dateza.test"
  end

  test "requires a brand-assigned moderator" do
    patch "/api/v1/admin/profile_photos/#{@photo.public_id}", params: { status: "approved" }
    assert_response :unauthorized

    ordinary_token, = Session.issue!(brand: @brand, user: @profile.user)
    patch "/api/v1/admin/profile_photos/#{@photo.public_id}",
      headers: bearer_headers(ordinary_token), params: { status: "approved" }
    assert_response :forbidden
  end

  test "pending approval makes a safe DateZA photo publicly deliverable and audits the decision" do
    assert_difference -> { SecurityEvent.where(event_type: "admin.profile_photo_moderated").count }, 1 do
      patch "/api/v1/admin/profile_photos/#{@photo.public_id}",
        headers: bearer_headers(@token), params: { status: "approved" }
    end

    assert_response :success
    payload = JSON.parse(response.body)
    assert payload.fetch("transitioned")
    assert_equal "approved", payload.dig("photo", "status")
    assert_equal "visible", payload.dig("photo", "visibility")
    assert @photo.reload.deliverable?

    event = SecurityEvent.where(event_type: "admin.profile_photo_moderated").last
    assert_equal @admin.id, event.metadata.fetch("admin_user_id")
    assert_equal @photo.public_id, event.metadata.fetch("profile_photo_id")
    assert_equal "approved", event.metadata.fetch("decision")
    assert_equal "manual_moderation_decision", event.metadata.fetch("reason_code")
  end

  test "pending rejection hides the photo and unpublishes a profile that loses photo eligibility" do
    @profile.update!(status: :active, visibility: :visible)
    assert Profiles::Completion.call(profile: @profile).complete?

    patch "/api/v1/admin/profile_photos/#{@photo.public_id}",
      headers: bearer_headers(@token), params: { status: "rejected" }

    assert_response :success
    assert @photo.reload.rejected?
    assert @photo.hidden?
    assert_not @photo.deliverable?
    assert @profile.reload.draft?
    assert @profile.hidden?
  end

  test "same terminal decision is idempotent and conflicting decision is rejected" do
    patch "/api/v1/admin/profile_photos/#{@photo.public_id}",
      headers: bearer_headers(@token), params: { status: "approved" }
    assert_response :success

    assert_no_difference -> { SecurityEvent.where(event_type: "admin.profile_photo_moderated").count } do
      patch "/api/v1/admin/profile_photos/#{@photo.public_id}",
        headers: bearer_headers(@token), params: { status: "approved" }
    end
    assert_response :success
    assert_not JSON.parse(response.body).fetch("transitioned")

    patch "/api/v1/admin/profile_photos/#{@photo.public_id}",
      headers: bearer_headers(@token), params: { status: "rejected" }
    assert_response :conflict
    assert_equal "profile_photo_moderation_conflict", JSON.parse(response.body).fetch("error")
  end

  test "invalid unknown deleted and cross-brand photos fail neutrally" do
    patch "/api/v1/admin/profile_photos/#{@photo.public_id}",
      headers: bearer_headers(@token), params: { status: "pending_review" }
    assert_response :unprocessable_entity
    assert_equal "invalid_photo_moderation_status", JSON.parse(response.body).fetch("error")

    other_brand = Brand.create!(slug: "hookus", name: "HookUs")
    foreign = create_ready_photo(profile: create_profile(brand: other_brand), visibility: :visible)
    @photo.update!(deleted_at: Time.current)

    [ @photo.public_id, foreign.public_id, SecureRandom.uuid ].each do |id|
      patch "/api/v1/admin/profile_photos/#{id}",
        headers: bearer_headers(@token), params: { status: "approved" }
      assert_response :not_found
      assert_equal "profile_photo_unavailable", JSON.parse(response.body).fetch("error")
    end
  end

  private

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end

  def create_profile(brand:)
    user = User.create!
    membership = BrandMembership.create!(brand:, user:)
    Profile.create!(brand:, user:, brand_membership: membership)
  end

  def create_ready_photo(profile:, visibility:)
    photo = ProfilePhoto.new(
      brand: profile.brand, user: profile.user, profile:, visibility:, status: :pending_review
    )
    fixture = Rails.root.join("test/fixtures/files/profile_photo.png")
    photo.image.attach(io: fixture.open, filename: "original.png", content_type: "image/png")
    photo.save!
    photo.display_image.attach(io: fixture.open, filename: "display.jpg", content_type: "image/jpeg")
    photo.update!(processing_state: :ready)
    photo
  end

  def create_admin(brand:)
    user = User.create!
    BrandMembership.create!(brand:, user:)
    admin_user = AdminUser.create!(user:, status: :active)
    role = AdminRole.find_or_create_by!(name: "moderator")
    AdminAssignment.create!(admin_user:, brand:, admin_role: role, status: :active)
    token, = Session.issue!(brand:, user:)
    [ admin_user, token ]
  end
end
