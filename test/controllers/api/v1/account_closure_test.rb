require "test_helper"

class Api::V1::AccountClosureTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @brand = Brand.create!(slug: "hookus", name: "HookUs")
    BrandDomain.create!(brand: @brand, host: "hookus.test")
    @ada = create_profile(brand: @brand, display_name: "Ada")
    @sam = create_profile(brand: @brand, display_name: "Sam")
    @sam_token, = Session.issue!(brand: @brand, user: @sam.user)
    @ada_token, = Session.issue!(brand: @brand, user: @ada.user)
    host! "hookus.test"
  end

  test "closure requires authentication and explicit confirmation" do
    delete "/api/v1/me"
    assert_response :unauthorized

    delete "/api/v1/me", headers: bearer_headers(@sam_token)
    assert_response :unprocessable_entity
    assert_equal "confirmation_required", JSON.parse(response.body).fetch("error")
    assert_not @sam.brand_membership.reload.left?
  end

  test "an authenticated user closes their own account" do
    assert_difference -> { AccountClosure.count }, 1 do
      close(@sam_token)
    end
    assert_response :success
    body = JSON.parse(response.body)
    assert body.fetch("closed")
    assert_not body.fetch("already_closed")
    assert_equal "pending", body.fetch("media_purge_state")

    membership = @sam.brand_membership.reload
    assert membership.left?
    @sam.reload
    assert @sam.deleted_at.present?
    assert_predicate @sam, :hidden?
    assert_nil @sam.display_name
    assert_nil @sam.bio
  end

  test "closure revokes every session for the brand and blocks re-authentication" do
    second_token, = Session.issue!(brand: @brand, user: @sam.user)

    close(@sam_token)
    assert_response :success

    [ @sam_token, second_token ].each do |token|
      get "/api/v1/me", headers: bearer_headers(token)
      assert_response :unauthorized
    end
    assert_equal 2, Session.where(user: @sam.user, brand: @brand).where.not(revoked_at: nil).count
  end

  test "a closed profile disappears from discovery and cannot be interacted with" do
    get "/api/v1/discovery", headers: bearer_headers(@ada_token)
    assert_includes JSON.parse(response.body).fetch("profiles").pluck("id"), @sam.public_id

    close(@sam_token)

    get "/api/v1/discovery", headers: bearer_headers(@ada_token)
    assert_not_includes JSON.parse(response.body).fetch("profiles").pluck("id"), @sam.public_id

    post "/api/v1/profiles/#{@sam.public_id}/likes", headers: bearer_headers(@ada_token)
    assert_response :not_found
    assert_equal "profile_unavailable", JSON.parse(response.body).fetch("error")
  end

  test "a closed user cannot act because their session is dead" do
    other = create_profile(brand: @brand)
    close(@sam_token)

    post "/api/v1/profiles/#{other.public_id}/likes", headers: bearer_headers(@sam_token)
    assert_response :unauthorized
    post "/api/v1/profiles/#{other.public_id}/pass", headers: bearer_headers(@sam_token)
    assert_response :unauthorized
  end

  test "closure ends matches and severs conversations while retaining shared history" do
    match = create_match(@ada, @sam)
    conversation = Messaging::StartConversation.call(user: @ada.user, brand: @brand, match_public_id: match.public_id).conversation
    Message.create!(brand: @brand, conversation:, sender_profile: @sam, body: "hi Ada")

    close(@sam_token)

    assert match.reload.status_ended?
    # Counterpart can no longer read the conversation, but the record + history remain.
    get "/api/v1/conversations/#{conversation.public_id}/messages", headers: bearer_headers(@ada_token)
    assert_response :not_found
    assert_equal "conversation_unavailable", JSON.parse(response.body).fetch("error")
    assert Conversation.exists?(conversation.id)
    assert_equal 1, conversation.messages.count
  end

  test "likes and passes are discarded from active product state" do
    Like.create!(brand: @brand, liker_profile: @sam, liked_profile: @ada)
    Like.create!(brand: @brand, liker_profile: @ada, liked_profile: @sam)
    ProfilePass.create!(brand: @brand, passer_profile: @sam, passed_profile: create_profile(brand: @brand))

    close(@sam_token)

    assert_empty Like.kept.where(brand: @brand).where("liker_profile_id = :id OR liked_profile_id = :id", id: @sam.id)
    assert_empty ProfilePass.kept.where(passer_profile: @sam)
  end

  test "location history is hard-deleted while photos are discarded and purge is enqueued" do
    ProfileLocation.create!(brand: @brand, profile: @sam, user: @sam.user, latitude: 1.0, longitude: 2.0,
      accuracy_meters: 5, source: "device", captured_at: Time.current)
    photo = attach_photo(@sam)

    assert_enqueued_with(job: Media::PurgeProfileMediaJob) do
      close(@sam_token)
    end

    assert_equal 0, ProfileLocation.where(profile: @sam).count
    assert photo.reload.deleted_at.present?
    assert_predicate photo, :hidden?
  end

  test "safety and identity records survive closure" do
    report = Report.create!(brand: @brand, reporter_profile: @ada, reported_profile: @sam, reason: :harassment)
    incoming_block = ProfileBlock.create!(brand: @brand, blocker_profile: @ada, blocked_profile: @sam)
    credential_count = @sam.user.credentials.count

    close(@sam_token)

    # Reports, blocks, and the network identity persist.
    assert Report.exists?(report.id)
    assert ProfileBlock.exists?(incoming_block.id)
    assert User.exists?(@sam.user_id)
    assert_equal credential_count, @sam.user.credentials.count
    assert SecurityEvent.where(event_type: "account.closed", user: @sam.user).exists?

    # The closed user drops off the blocker's block-management list.
    get "/api/v1/blocks", headers: bearer_headers(@ada_token)
    assert_response :success
    assert_empty JSON.parse(response.body).fetch("blocks")
  end

  test "an active enforcement against the user survives closure" do
    admin_user = AdminUser.create!(user: User.create!, status: :active)
    enforcement = AccountEnforcement.create!(brand: @brand, user: @sam.user,
      brand_membership: @sam.brand_membership, profile: @sam, admin_user:)

    close(@sam_token)

    assert AccountEnforcement.exists?(enforcement.id)
  end

  test "brand-level closure never touches another brand's data" do
    other_brand = Brand.create!(slug: "other", name: "Other")
    other_membership = BrandMembership.create!(brand: other_brand, user: @sam.user)
    other_profile = Profile.create!(brand: other_brand, user: @sam.user, brand_membership: other_membership,
      display_name: "Sam2", birthdate: 30.years.ago.to_date, gender: "person", status: :active, visibility: :visible)
    other_token, = Session.issue!(brand: other_brand, user: @sam.user)
    current_device = DeviceRegistration.create!(
      brand: @brand, user: @sam.user, brand_membership: @sam.brand_membership,
      platform: :ios, token: "current-brand-device", last_seen_at: Time.current
    )
    other_device = DeviceRegistration.create!(
      brand: other_brand, user: @sam.user, brand_membership: other_membership,
      platform: :ios, token: "other-brand-device", last_seen_at: Time.current
    )

    close(@sam_token)

    assert other_membership.reload.active?
    assert_nil other_profile.reload.deleted_at
    assert_nil Session.find_by(token_digest: Session.digest_token(other_token)).revoked_at
    assert current_device.reload.revoked_at
    assert_not current_device.enabled?
    assert_nil other_device.reload.revoked_at
    assert other_device.enabled?
  end

  test "closure is idempotent at the domain level" do
    Accounts::CloseAccount.call(user: @sam.user, brand: @brand)

    assert_no_difference -> { AccountClosure.count } do
      result = Accounts::CloseAccount.call(user: @sam.user, brand: @brand)
      assert result.already_closed
    end
  end

  test "the full closure lifecycle removes the user and preserves shared and safety records" do
    observer = create_profile(brand: @brand, display_name: "Obs")
    observer_token, = Session.issue!(brand: @brand, user: observer.user)
    second_token, = Session.issue!(brand: @brand, user: @sam.user)
    match = create_match(@ada, @sam)
    conversation = Messaging::StartConversation.call(user: @ada.user, brand: @brand, match_public_id: match.public_id).conversation
    Message.create!(brand: @brand, conversation:, sender_profile: @sam, body: "hey")
    Report.create!(brand: @brand, reporter_profile: @ada, reported_profile: @sam, reason: :harassment)
    attach_photo(@sam)

    get "/api/v1/discovery", headers: bearer_headers(observer_token)
    assert_includes JSON.parse(response.body).fetch("profiles").pluck("id"), @sam.public_id

    assert_enqueued_with(job: Media::PurgeProfileMediaJob) { close(@sam_token) }
    assert_response :success

    [ @sam_token, second_token ].each do |token|
      get "/api/v1/me", headers: bearer_headers(token)
      assert_response :unauthorized
    end
    get "/api/v1/discovery", headers: bearer_headers(observer_token)
    assert_not_includes JSON.parse(response.body).fetch("profiles").pluck("id"), @sam.public_id
    assert match.reload.status_ended?
    assert_equal 1, conversation.messages.count
    assert_equal 1, Report.where(reported_profile: @sam).count
    assert User.exists?(@sam.user_id)
  end

  private

  def close(token)
    delete "/api/v1/me", headers: bearer_headers(token), params: { confirmation: "close" }
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
