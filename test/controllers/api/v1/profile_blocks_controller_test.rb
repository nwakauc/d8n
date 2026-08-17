require "test_helper"

class Api::V1::ProfileBlocksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @brand = Brand.create!(slug: "hookus", name: "HookUs")
    BrandDomain.create!(brand: @brand, host: "hookus.test")
    @viewer = create_profile(brand: @brand, display_name: "Ada")
    @target = create_profile(brand: @brand, display_name: "Sam")
    @token, = Session.issue!(brand: @brand, user: @viewer.user)
    @target_token, = Session.issue!(brand: @brand, user: @target.user)
    host! "hookus.test"
  end

  test "requires authentication" do
    post "/api/v1/profiles/#{@target.public_id}/block"
    assert_response :unauthorized

    delete "/api/v1/profiles/#{@target.public_id}/block"
    assert_response :unauthorized

    get "/api/v1/blocks"
    assert_response :unauthorized
  end

  test "lists only my outgoing blocks newest first with minimal profile info" do
    other = create_profile(brand: @brand, display_name: "Kai")
    older = ProfileBlock.create!(brand: @brand, blocker_profile: @viewer, blocked_profile: @target, created_at: 2.days.ago)
    newer = ProfileBlock.create!(brand: @brand, blocker_profile: @viewer, blocked_profile: other, created_at: 1.hour.ago)
    # Incoming block against the viewer must never be disclosed to them.
    ProfileBlock.create!(brand: @brand, blocker_profile: other, blocked_profile: @viewer)

    get "/api/v1/blocks", headers: bearer_headers(@token)

    assert_response :success
    blocks = JSON.parse(response.body).fetch("blocks")
    assert_equal [ other.public_id, @target.public_id ], blocks.map { |b| b.fetch("profile").fetch("id") }
    assert_equal({ "id" => other.public_id, "display_name" => "Kai" }, blocks.first.fetch("profile"))
    assert blocks.first.key?("blocked_at")
    assert_equal newer.created_at.iso8601, blocks.first.fetch("blocked_at")
    assert_equal older.created_at.iso8601, blocks.last.fetch("blocked_at")
  end

  test "omits soft-deleted targets and other-brand blocks from the list" do
    ProfileBlock.create!(brand: @brand, blocker_profile: @viewer, blocked_profile: @target)
    @target.update!(deleted_at: Time.current)

    get "/api/v1/blocks", headers: bearer_headers(@token)

    assert_response :success
    assert_empty JSON.parse(response.body).fetch("blocks")
  end

  test "blocks idempotently and removes positive relationship state" do
    Like.create!(brand: @brand, liker_profile: @viewer, liked_profile: @target)
    Like.create!(brand: @brand, liker_profile: @target, liked_profile: @viewer)
    match = create_match(@viewer, @target)

    assert_difference -> { ProfileBlock.count }, 1 do
      post "/api/v1/profiles/#{@target.public_id}/block", headers: bearer_headers(@token)
    end

    assert_response :created
    assert JSON.parse(response.body).fetch("blocked")
    assert JSON.parse(response.body).fetch("created")
    assert_predicate match.reload, :status_ended?
    assert_empty Like.kept.where(brand: @brand, liker_profile_id: [ @viewer.id, @target.id ])

    assert_no_difference -> { ProfileBlock.count } do
      post "/api/v1/profiles/#{@target.public_id}/block", headers: bearer_headers(@token)
    end
    assert_response :success
    assert_not JSON.parse(response.body).fetch("created")
  end

  test "uses the same unavailable response for self unknown and cross-brand targets" do
    other_brand = Brand.create!(slug: "other", name: "Other")
    other_profile = create_profile(brand: other_brand)

    [ @viewer.public_id, SecureRandom.uuid, other_profile.public_id ].each do |profile_id|
      post "/api/v1/profiles/#{profile_id}/block", headers: bearer_headers(@token)

      assert_response :not_found
      assert_equal "profile_unavailable", JSON.parse(response.body).fetch("error")
    end
  end

  test "does not block a soft-deleted target" do
    @target.update!(deleted_at: Time.current)

    assert_no_difference -> { ProfileBlock.count } do
      post "/api/v1/profiles/#{@target.public_id}/block", headers: bearer_headers(@token)
    end

    assert_response :not_found
    assert_equal "profile_unavailable", JSON.parse(response.body).fetch("error")
  end

  test "unblocks only the current profile direction and remains idempotent" do
    outgoing = ProfileBlock.create!(brand: @brand, blocker_profile: @viewer, blocked_profile: @target)
    incoming = ProfileBlock.create!(brand: @brand, blocker_profile: @target, blocked_profile: @viewer)

    delete "/api/v1/profiles/#{@target.public_id}/block", headers: bearer_headers(@token)

    assert_response :no_content
    assert outgoing.reload.deleted_at.present?
    assert_nil incoming.reload.deleted_at

    delete "/api/v1/profiles/#{@target.public_id}/block", headers: bearer_headers(@token)
    assert_response :no_content
  end

  test "does not resolve soft-deleted unknown or cross-brand targets while unblocking" do
    outgoing = ProfileBlock.create!(brand: @brand, blocker_profile: @viewer, blocked_profile: @target)
    @target.update!(deleted_at: Time.current)
    other_brand = Brand.create!(slug: "other", name: "Other")
    other_profile = create_profile(brand: other_brand)

    [ @target.public_id, SecureRandom.uuid, other_profile.public_id ].each do |profile_id|
      delete "/api/v1/profiles/#{profile_id}/block", headers: bearer_headers(@token)
      assert_response :no_content
    end

    assert_nil outgoing.reload.deleted_at
  end

  test "enforces either block direction in discovery likes and passes" do
    post "/api/v1/profiles/#{@target.public_id}/block", headers: bearer_headers(@token)
    assert_response :created

    get "/api/v1/discovery", headers: bearer_headers(@token)
    assert_response :success
    assert_not_includes JSON.parse(response.body).fetch("profiles").pluck("id"), @target.public_id

    get "/api/v1/discovery", headers: bearer_headers(@target_token)
    assert_response :success
    assert_not_includes JSON.parse(response.body).fetch("profiles").pluck("id"), @viewer.public_id

    post "/api/v1/profiles/#{@viewer.public_id}/likes", headers: bearer_headers(@target_token)
    assert_response :not_found
    assert_equal "profile_unavailable", JSON.parse(response.body).fetch("error")

    post "/api/v1/profiles/#{@viewer.public_id}/pass", headers: bearer_headers(@target_token)
    assert_response :not_found
    assert_equal "profile_unavailable", JSON.parse(response.body).fetch("error")
  end

  test "hides manually retained match and conversation metadata in both directions" do
    match = create_match(@viewer, @target)
    conversation = Messaging::StartConversation.call(
      user: @viewer.user,
      brand: @brand,
      match_public_id: match.public_id
    ).conversation
    assert conversation.present?

    post "/api/v1/profiles/#{@target.public_id}/block", headers: bearer_headers(@token)
    assert_response :created

    match.update!(status: :active)
    get "/api/v1/matches", headers: bearer_headers(@target_token)
    assert_response :success
    assert_empty JSON.parse(response.body).fetch("matches")

    get "/api/v1/conversations", headers: bearer_headers(@target_token)
    assert_response :success
    assert_empty JSON.parse(response.body).fetch("conversations")

    post "/api/v1/matches/#{match.public_id}/conversation", headers: bearer_headers(@target_token)
    assert_response :not_found
    assert_equal "conversation_unavailable", JSON.parse(response.body).fetch("error")
  end

  test "unblocking permits future interaction without restoring ended relationships" do
    match = create_match(@viewer, @target)
    post "/api/v1/profiles/#{@target.public_id}/block", headers: bearer_headers(@token)

    delete "/api/v1/profiles/#{@target.public_id}/block", headers: bearer_headers(@token)
    assert_response :no_content
    assert_predicate match.reload, :status_ended?
    assert_empty Like.kept.where(brand: @brand, liker_profile_id: [ @viewer.id, @target.id ])

    post "/api/v1/profiles/#{@target.public_id}/likes", headers: bearer_headers(@token)
    assert_response :created
  end

  private

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end

  def create_profile(brand:, display_name: nil)
    user = User.create!
    membership = BrandMembership.create!(brand:, user:)
    profile = Profile.create!(
      brand:, user:, brand_membership: membership, display_name:,
      birthdate: 30.years.ago.to_date, gender: "person", status: :active, visibility: :visible
    )
    ProfilePreference.create!(
      brand:, user:, profile:, min_age: 18, max_age: 80, interested_in: [ "person" ]
    )
    profile
  end

  def create_match(first, second)
    profile_a_id, profile_b_id = Match.canonical_pair(first.id, second.id)
    Match.create!(brand: first.brand, profile_a_id:, profile_b_id:)
  end
end
