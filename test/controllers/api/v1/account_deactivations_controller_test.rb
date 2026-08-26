require "test_helper"

class Api::V1::AccountDeactivationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @brand = Brand.create!(slug: "hookus", name: "HookUs")
    BrandDomain.create!(brand: @brand, host: "hookus.test")
    @ada = create_profile(brand: @brand, display_name: "Ada")
    @sam = create_profile(brand: @brand, display_name: "Sam")
    @sam_token, = Session.issue!(brand: @brand, user: @sam.user)
    @ada_token, = Session.issue!(brand: @brand, user: @ada.user)
    host! "hookus.test"
  end

  test "deactivation requires authentication and explicit confirmation" do
    post "/api/v1/account/deactivation"
    assert_response :unauthorized

    post "/api/v1/account/deactivation", headers: bearer_headers(@sam_token)
    assert_response :unprocessable_entity
    assert_equal "confirmation_required", JSON.parse(response.body).fetch("error")
    assert_not @sam.brand_membership.reload.deactivated?
  end

  test "an authenticated member deactivates their own account and loses their session" do
    deactivate(@sam_token)
    assert_response :success
    body = JSON.parse(response.body)
    assert body.fetch("deactivated")
    assert_not body.fetch("already_deactivated")
    assert @sam.brand_membership.reload.deactivated?

    get "/api/v1/me", headers: bearer_headers(@sam_token)
    assert_response :unauthorized
  end

  test "repeated deactivation is idempotent at the domain level" do
    deactivate(@sam_token)
    assert_response :success

    result = Accounts::DeactivateAccount.call(user: @sam.user, brand: @brand)
    assert result.already_deactivated
    assert @sam.brand_membership.reload.deactivated?
  end

  test "a token issued after deactivation still cannot re-deactivate without a live session" do
    deactivate(@sam_token)
    assert_response :success

    second_token, = Session.issue!(brand: @brand, user: @sam.user)
    post "/api/v1/account/deactivation", headers: bearer_headers(second_token), params: { confirmation: "deactivate" }
    assert_response :unauthorized
  end

  test "deactivation preserves profile, photos, and preferences intact" do
    photo = attach_photo(@sam)
    display_name = @sam.display_name

    deactivate(@sam_token)
    assert_response :success

    @sam.reload
    assert_nil @sam.deleted_at
    assert_equal display_name, @sam.display_name
    assert photo.reload.persisted?
    assert_nil photo.deleted_at
    assert ProfilePreference.kept.exists?(profile: @sam)
  end

  test "a deactivated profile disappears from discovery and cannot be interacted with" do
    get "/api/v1/discovery", headers: bearer_headers(@ada_token)
    assert_includes JSON.parse(response.body).fetch("profiles").pluck("id"), @sam.public_id

    deactivate(@sam_token)
    assert_response :success

    get "/api/v1/discovery", headers: bearer_headers(@ada_token)
    assert_not_includes JSON.parse(response.body).fetch("profiles").pluck("id"), @sam.public_id

    post "/api/v1/profiles/#{@sam.public_id}/likes", headers: bearer_headers(@ada_token)
    assert_response :not_found
    assert_equal "profile_unavailable", JSON.parse(response.body).fetch("error")
  end

  test "a deactivated member cannot act because their session is dead" do
    other = create_profile(brand: @brand)
    deactivate(@sam_token)
    assert_response :success

    post "/api/v1/profiles/#{other.public_id}/likes", headers: bearer_headers(@sam_token)
    assert_response :unauthorized
  end

  test "deactivation revokes devices but leaves matches and conversations intact" do
    match = create_match(@ada, @sam)
    conversation = Messaging::StartConversation.call(user: @ada.user, brand: @brand, match_public_id: match.public_id).conversation
    Message.create!(brand: @brand, conversation:, sender_profile: @sam, body: "hi Ada")
    device = DeviceRegistration.create!(
      brand: @brand, user: @sam.user, brand_membership: @sam.brand_membership,
      platform: :ios, token: "sam-device", last_seen_at: Time.current
    )

    deactivate(@sam_token)
    assert_response :success

    assert_not match.reload.status_ended?
    assert Conversation.exists?(conversation.id)
    assert_equal 1, conversation.messages.count
    assert device.reload.revoked_at
    assert_not device.enabled?
  end

  test "deactivation never touches another brand's membership" do
    other_brand = Brand.create!(slug: "other", name: "Other")
    other_membership = BrandMembership.create!(brand: other_brand, user: @sam.user)

    deactivate(@sam_token)
    assert_response :success

    assert other_membership.reload.active?
  end

  private

  def deactivate(token)
    post "/api/v1/account/deactivation", headers: bearer_headers(token), params: { confirmation: "deactivate" }
  end

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end

  def attach_photo(profile)
    photo = ProfilePhoto.new(profile:, user: profile.user, brand: profile.brand, position: 0)
    photo.image.attach(io: StringIO.new("rawbytes"), filename: "a.jpg", content_type: "image/jpeg")
    photo.save!
    photo
  end

  def create_profile(brand:, display_name: nil)
    user = User.create!
    membership = BrandMembership.create!(brand:, user:)
    profile = Profile.create!(
      brand:, user:, brand_membership: membership, display_name:,
      birthdate: 30.years.ago.to_date, gender: "person", status: :active, visibility: :visible
    )
    ProfilePreference.create!(brand:, user:, profile:, min_age: 18, max_age: 80, interested_in: [ "person" ])
    profile
  end

  def create_match(first, second)
    profile_a_id, profile_b_id = Match.canonical_pair(first.id, second.id)
    Match.create!(brand: first.brand, profile_a_id:, profile_b_id:)
  end
end
