require "test_helper"
require "vips"

class Api::V1::MatchesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @brand = Brand.create!(slug: "hookus", name: "HookUs")
    BrandDomain.create!(brand: @brand, host: "hookus.test")
    @viewer = create_profile(gender: "woman", interested_in: [ "man" ], display_name: "Ada")
    @token, = Session.issue!(brand: @brand, user: @viewer.user)
    host! "hookus.test"
  end

  test "requires authentication" do
    get "/api/v1/matches"

    assert_response :unauthorized
  end

  test "lists only current-profile matches with public data" do
    candidate = create_profile(gender: "man", interested_in: [ "woman" ], display_name: "Sam")
    match = create_match(@viewer, candidate)
    outsider_a = create_profile(gender: "woman", interested_in: [ "man" ])
    outsider_b = create_profile(gender: "man", interested_in: [ "woman" ])
    create_match(outsider_a, outsider_b)

    get "/api/v1/matches", headers: bearer_headers(@token)

    assert_response :success
    payload = JSON.parse(response.body).fetch("matches").sole
    assert_equal match.public_id, payload.fetch("id")
    assert_equal candidate.public_id, payload.fetch("profile").fetch("id")
    assert_equal "Sam", payload.fetch("profile").fetch("display_name")
    assert_not payload.fetch("profile").key?("birthdate")
    assert_not payload.fetch("profile").key?("user_id")
  end

  test "uses a viewer-bound cursor" do
    candidates = 3.times.map { create_profile(gender: "man", interested_in: [ "woman" ]) }
    matches = candidates.map { |candidate| create_match(@viewer, candidate) }
    matches.each_with_index do |match, index|
      match.update_columns(created_at: Time.utc(2026, 8, 13, 12, 0, index), updated_at: Time.current)
    end

    get "/api/v1/matches", headers: bearer_headers(@token), params: { limit: 2 }
    first_page = JSON.parse(response.body)

    assert_response :success
    assert_equal [ matches[2].public_id, matches[1].public_id ], first_page.fetch("matches").pluck("id")

    get "/api/v1/matches",
      headers: bearer_headers(@token),
      params: { limit: 2, cursor: first_page.fetch("next_cursor") }

    assert_response :success
    assert_equal [ matches[0].public_id ], JSON.parse(response.body).fetch("matches").pluck("id")
  end

  test "does not expose a match whose counterpart becomes unavailable" do
    candidate = create_profile(gender: "man", interested_in: [ "woman" ])
    create_match(@viewer, candidate)
    candidate.user.update!(status: :suspended)

    get "/api/v1/matches", headers: bearer_headers(@token)

    assert_response :success
    assert_empty JSON.parse(response.body).fetch("matches")
  end

  test "exposes the matched profile's safe display derivative, never the raw original" do
    candidate = create_profile(gender: "man", interested_in: [ "woman" ], display_name: "Sam")
    create_match(@viewer, candidate)
    jpeg = Vips::Image.black(60, 40).add([ 120 ]).cast("uchar").write_to_buffer(".jpg")
    photo = ProfilePhoto.new(brand: @brand, user: candidate.user, profile: candidate, position: 0, visibility: :visible)
    photo.image.attach(io: StringIO.new(jpeg), filename: "original.jpg", content_type: "image/jpeg")
    photo.save!
    photo.display_image.attach(io: StringIO.new(jpeg), filename: "display.jpg", content_type: "image/jpeg")
    photo.update!(processing_state: :ready)

    get "/api/v1/matches", headers: bearer_headers(@token)

    assert_response :success
    photos = JSON.parse(response.body).fetch("matches").sole.fetch("profile").fetch("photos")
    assert_equal 1, photos.size
    assert photos.sole.fetch("url").present?
    assert_includes photos.sole.fetch("url"), "display.jpg"
    assert_not_includes response.body, photo.image.blob.key
  end

  test "rejects invalid cursors and limits" do
    get "/api/v1/matches", headers: bearer_headers(@token), params: { cursor: "invalid" }
    assert_response :unprocessable_entity
    assert_equal "invalid_cursor", JSON.parse(response.body).fetch("error")

    get "/api/v1/matches", headers: bearer_headers(@token), params: { limit: 51 }
    assert_response :unprocessable_entity
    assert_equal "invalid_limit", JSON.parse(response.body).fetch("error")
  end

  # -- POST /api/v1/matches/:match_id/unmatch --------------------------------

  test "unmatch requires authentication" do
    candidate = create_profile(gender: "man", interested_in: [ "woman" ])
    match = create_match(@viewer, candidate)

    post "/api/v1/matches/#{match.public_id}/unmatch"

    assert_response :unauthorized
  end

  test "a participant can unmatch an active match" do
    candidate = create_profile(gender: "man", interested_in: [ "woman" ])
    match = create_match(@viewer, candidate)
    Like.create!(brand: @brand, liker_profile: @viewer, liked_profile: candidate)
    Like.create!(brand: @brand, liker_profile: candidate, liked_profile: @viewer)

    post "/api/v1/matches/#{match.public_id}/unmatch", headers: bearer_headers(@token)

    assert_response :no_content
    assert_predicate match.reload, :status_ended?
    assert_empty Like.kept.where(brand: @brand, liker_profile_id: [ @viewer.id, candidate.id ])
    assert_not ProfileBlock.kept.exists?(brand: @brand, blocker_profile: @viewer, blocked_profile: candidate)
    assert_not ProfileBlock.kept.exists?(brand: @brand, blocker_profile: candidate, blocked_profile: @viewer)
  end

  test "the other participant can also unmatch the same match" do
    candidate = create_profile(gender: "man", interested_in: [ "woman" ])
    match = create_match(@viewer, candidate)
    candidate_token, = Session.issue!(brand: @brand, user: candidate.user)

    post "/api/v1/matches/#{match.public_id}/unmatch", headers: bearer_headers(candidate_token)

    assert_response :no_content
    assert_predicate match.reload, :status_ended?
  end

  test "unmatch removes the match from the match list and both Likes surfaces" do
    candidate = create_profile(gender: "man", interested_in: [ "woman" ])
    match = create_match(@viewer, candidate)
    Like.create!(brand: @brand, liker_profile: @viewer, liked_profile: candidate)
    Like.create!(brand: @brand, liker_profile: candidate, liked_profile: @viewer)

    post "/api/v1/matches/#{match.public_id}/unmatch", headers: bearer_headers(@token)
    assert_response :no_content

    get "/api/v1/matches", headers: bearer_headers(@token)
    assert_empty JSON.parse(response.body).fetch("matches")

    get "/api/v1/likes/incoming", headers: bearer_headers(@token)
    assert_empty JSON.parse(response.body).fetch("likes")

    get "/api/v1/likes/outgoing", headers: bearer_headers(@token)
    assert_empty JSON.parse(response.body).fetch("likes")
  end

  test "unmatch ends messaging access but retains the conversation as read-only history" do
    candidate = create_profile(gender: "man", interested_in: [ "woman" ])
    match = create_match(@viewer, candidate)
    conversation = Messaging::StartConversation.call(
      user: @viewer.user, brand: @brand, match_public_id: match.public_id
    ).conversation
    Messaging::SendMessage.call(
      user: @viewer.user, brand: @brand, conversation_public_id: conversation.public_id, body: "hi there"
    )

    post "/api/v1/matches/#{match.public_id}/unmatch", headers: bearer_headers(@token)
    assert_response :no_content

    get "/api/v1/conversations", headers: bearer_headers(@token)
    assert_response :success
    listed = JSON.parse(response.body).fetch("conversations")
    assert_equal conversation.public_id, listed.sole.fetch("id")
    assert_equal "hi there", listed.sole.dig("last_message", "body")

    get "/api/v1/conversations/#{conversation.public_id}/messages", headers: bearer_headers(@token)
    assert_response :not_found
    assert_equal "conversation_unavailable", JSON.parse(response.body).fetch("error")

    post "/api/v1/conversations/#{conversation.public_id}/messages",
      headers: bearer_headers(@token), params: { body: "still there?" }
    assert_response :not_found
    assert_equal "conversation_unavailable", JSON.parse(response.body).fetch("error")
    assert_equal 1, Message.kept.where(conversation:).count
  end

  test "a non-participant cannot unmatch someone else's match" do
    candidate = create_profile(gender: "man", interested_in: [ "woman" ])
    match = create_match(@viewer, candidate)
    outsider = create_profile(gender: "woman", interested_in: [ "man" ])
    outsider_token, = Session.issue!(brand: @brand, user: outsider.user)

    post "/api/v1/matches/#{match.public_id}/unmatch", headers: bearer_headers(outsider_token)

    assert_response :not_found
    assert_equal "match_unavailable", JSON.parse(response.body).fetch("error")
    assert_predicate match.reload, :status_active?
  end

  test "returns the same not-found response for unknown and cross-brand matches" do
    other_brand = Brand.create!(slug: "date9ja", name: "Date9ja")
    BrandDomain.create!(brand: other_brand, host: "date9ja.test")
    other_a = create_profile(brand: other_brand, gender: "woman", interested_in: [ "man" ])
    other_b = create_profile(brand: other_brand, gender: "man", interested_in: [ "woman" ])
    profile_a_id, profile_b_id = Match.canonical_pair(other_a.id, other_b.id)
    cross_brand_match = Match.create!(brand: other_brand, profile_a_id:, profile_b_id:)

    [ SecureRandom.uuid, cross_brand_match.public_id ].each do |match_id|
      post "/api/v1/matches/#{match_id}/unmatch", headers: bearer_headers(@token)
      assert_response :not_found
      assert_equal "match_unavailable", JSON.parse(response.body).fetch("error")
    end
  end

  test "unmatch is idempotent under retry" do
    candidate = create_profile(gender: "man", interested_in: [ "woman" ])
    match = create_match(@viewer, candidate)

    post "/api/v1/matches/#{match.public_id}/unmatch", headers: bearer_headers(@token)
    assert_response :no_content

    assert_no_difference -> { Match.count } do
      post "/api/v1/matches/#{match.public_id}/unmatch", headers: bearer_headers(@token)
    end

    assert_response :no_content
    assert_predicate match.reload, :status_ended?
  end

  test "unmatching an already-ended (blocked) match is a safe no-op and does not touch the block" do
    candidate = create_profile(gender: "man", interested_in: [ "woman" ])
    match = create_match(@viewer, candidate)
    Trust::BlockProfile.call(user: @viewer.user, brand: @brand, target_public_id: candidate.public_id)
    assert_predicate match.reload, :status_ended?

    post "/api/v1/matches/#{match.public_id}/unmatch", headers: bearer_headers(@token)

    assert_response :no_content
    assert ProfileBlock.kept.exists?(brand: @brand, blocker_profile: @viewer, blocked_profile: candidate)
  end

  test "a Like-created match can be unmatched, and the pair can freely like each other again later" do
    candidate = create_profile(gender: "man", interested_in: [ "woman" ])
    Like.create!(brand: @brand, liker_profile: candidate, liked_profile: @viewer)
    post "/api/v1/profiles/#{candidate.public_id}/likes", headers: bearer_headers(@token)
    assert_response :created
    match = Match.last

    post "/api/v1/matches/#{match.public_id}/unmatch", headers: bearer_headers(@token)
    assert_response :no_content

    assert_difference -> { Like.count }, 1 do
      post "/api/v1/profiles/#{candidate.public_id}/likes", headers: bearer_headers(@token)
    end
    assert_response :created
    assert_equal false, JSON.parse(response.body).fetch("matched")

    candidate_token, = Session.issue!(brand: @brand, user: candidate.user)
    assert_difference -> { Match.count }, 1 do
      post "/api/v1/profiles/#{@viewer.public_id}/likes", headers: bearer_headers(candidate_token)
    end
    assert_response :created
    assert JSON.parse(response.body).fetch("matched")
    assert_not_equal match.public_id, JSON.parse(response.body).fetch("match_id")
  end

  test "an opener-created match can be unmatched the same way as a Like-created match" do
    candidate = create_profile(gender: "man", interested_in: [ "woman" ])
    hook = Hooks::SendHook.call(user: candidate.user, brand: @brand, target_public_id: @viewer.public_id, message: "hi").hook
    conversation = Hooks::ReplyToHook.call(
      user: @viewer.user, brand: @brand, hook_public_id: hook.public_id, message: "hey!"
    ).conversation
    match = conversation.match

    post "/api/v1/matches/#{match.public_id}/unmatch", headers: bearer_headers(@token)

    assert_response :no_content
    assert_predicate match.reload, :status_ended?
    get "/api/v1/matches", headers: bearer_headers(@token)
    assert_empty JSON.parse(response.body).fetch("matches")
  end

  test "blocking an active match still works exactly as before and is independent of unmatch" do
    candidate = create_profile(gender: "man", interested_in: [ "woman" ])
    match = create_match(@viewer, candidate)

    post "/api/v1/profiles/#{candidate.public_id}/block", headers: bearer_headers(@token)

    assert_response :created
    assert_predicate match.reload, :status_ended?
    assert ProfileBlock.kept.exists?(brand: @brand, blocker_profile: @viewer, blocked_profile: candidate)
  end

  private

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end

  def create_profile(brand: @brand, gender:, interested_in:, display_name: nil)
    user = User.create!
    membership = BrandMembership.create!(brand:, user:)
    profile = Profile.create!(
      brand:, user:, brand_membership: membership, display_name:, gender:,
      birthdate: 30.years.ago.to_date, status: :active, visibility: :visible
    )
    ProfilePreference.create!(
      brand:, user:, profile:, min_age: 25, max_age: 40, interested_in:
    )
    profile
  end

  def create_match(first, second)
    profile_a_id, profile_b_id = Match.canonical_pair(first.id, second.id)
    Match.create!(brand: first.brand, profile_a_id:, profile_b_id:)
  end
end
