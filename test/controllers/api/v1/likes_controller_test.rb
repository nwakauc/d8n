require "test_helper"

class Api::V1::LikesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @brand = Brand.create!(slug: "hookus", name: "HookUs")
    BrandDomain.create!(brand: @brand, host: "hookus.test")
    @viewer = create_profile(gender: "woman", interested_in: [ "man" ])
    @candidate = create_profile(gender: "man", interested_in: [ "woman" ])
    @token, = Session.issue!(brand: @brand, user: @viewer.user)
    host! "hookus.test"
  end

  test "requires authentication" do
    post "/api/v1/profiles/#{@candidate.public_id}/likes"

    assert_response :unauthorized
  end

  test "creates an idempotent brand-scoped like" do
    assert_difference -> { Like.count }, 1 do
      post "/api/v1/profiles/#{@candidate.public_id}/likes", headers: bearer_headers(@token)
    end

    assert_response :created
    first = JSON.parse(response.body)
    assert_equal true, first.fetch("liked")
    assert_equal false, first.fetch("matched")
    assert_equal true, first.fetch("created")

    assert_no_difference -> { Like.count } do
      post "/api/v1/profiles/#{@candidate.public_id}/likes", headers: bearer_headers(@token)
    end

    assert_response :success
    assert_equal false, JSON.parse(response.body).fetch("created")
  end

  test "replaces an existing pass with a like" do
    profile_pass = ProfilePass.create!(
      brand: @brand, passer_profile: @viewer, passed_profile: @candidate
    )

    post "/api/v1/profiles/#{@candidate.public_id}/likes", headers: bearer_headers(@token)

    assert_response :created
    assert profile_pass.reload.deleted_at.present?
    assert Like.kept.exists?(liker_profile: @viewer, liked_profile: @candidate)
  end

  test "creates one canonical match when the like is mutual" do
    Like.create!(brand: @brand, liker_profile: @candidate, liked_profile: @viewer)

    assert_difference -> { Match.count }, 1 do
      post "/api/v1/profiles/#{@candidate.public_id}/likes", headers: bearer_headers(@token)
    end

    assert_response :created
    payload = JSON.parse(response.body)
    match = Match.last
    assert_equal true, payload.fetch("matched")
    assert_equal match.public_id, payload.fetch("match_id")
    assert_operator match.profile_a_id, :<, match.profile_b_id
  end

  test "returns the same not-found response for self cross-brand and hidden targets" do
    other_brand = Brand.create!(slug: "date9ja", name: "Date9ja")
    other = create_profile(brand: other_brand, gender: "man", interested_in: [ "woman" ])
    hidden = create_profile(gender: "man", interested_in: [ "woman" ])
    hidden.update!(visibility: :hidden)

    [ @viewer.public_id, other.public_id, hidden.public_id, SecureRandom.uuid ].each do |public_id|
      post "/api/v1/profiles/#{public_id}/likes", headers: bearer_headers(@token)
      assert_response :not_found
      assert_equal "profile_unavailable", JSON.parse(response.body).fetch("error")
    end
  end

  # -- GET /api/v1/likes/incoming ------------------------------------------

  test "incoming requires authentication" do
    get "/api/v1/likes/incoming"

    assert_response :unauthorized
  end

  test "incoming lists profiles who liked the viewer, newest first" do
    older = create_profile(gender: "man", interested_in: [ "woman" ], display_name: "Older")
    newer = create_profile(gender: "man", interested_in: [ "woman" ], display_name: "Newer")
    like_older = create_like(older, @viewer)
    like_older.update_columns(created_at: 2.days.ago)
    create_like(newer, @viewer)

    get "/api/v1/likes/incoming", headers: bearer_headers(@token)

    assert_response :success
    payload = JSON.parse(response.body).fetch("likes")
    assert_equal [ "Newer", "Older" ], payload.pluck("profile").pluck("display_name")
    assert payload.first.fetch("liked_at").present?
    assert_not payload.first.fetch("profile").key?("user_id")
  end

  test "incoming excludes a pair with an active match" do
    other = create_profile(gender: "man", interested_in: [ "woman" ])
    create_like(other, @viewer)
    create_match(@viewer, other)

    get "/api/v1/likes/incoming", headers: bearer_headers(@token)

    assert_response :success
    assert_empty JSON.parse(response.body).fetch("likes")
  end

  test "incoming excludes a liker the viewer has blocked" do
    liker = create_profile(gender: "man", interested_in: [ "woman" ])
    create_like(liker, @viewer)
    create_block(blocker: @viewer, blocked: liker)

    get "/api/v1/likes/incoming", headers: bearer_headers(@token)

    assert_response :success
    assert_empty JSON.parse(response.body).fetch("likes")
  end

  test "incoming excludes a liker who has blocked the viewer" do
    liker = create_profile(gender: "man", interested_in: [ "woman" ])
    create_like(liker, @viewer)
    create_block(blocker: liker, blocked: @viewer)

    get "/api/v1/likes/incoming", headers: bearer_headers(@token)

    assert_response :success
    assert_empty JSON.parse(response.body).fetch("likes")
  end

  test "incoming excludes a suspended liker" do
    liker = create_profile(gender: "man", interested_in: [ "woman" ])
    create_like(liker, @viewer)
    liker.update!(status: :suspended)

    get "/api/v1/likes/incoming", headers: bearer_headers(@token)

    assert_response :success
    assert_empty JSON.parse(response.body).fetch("likes")
  end

  test "incoming excludes a liker whose account is closed" do
    liker = create_profile(gender: "man", interested_in: [ "woman" ])
    create_like(liker, @viewer)
    liker.user.update!(status: :closed)

    get "/api/v1/likes/incoming", headers: bearer_headers(@token)

    assert_response :success
    assert_empty JSON.parse(response.body).fetch("likes")
  end

  test "incoming excludes a discarded like" do
    liker = create_profile(gender: "man", interested_in: [ "woman" ])
    like = create_like(liker, @viewer)
    like.update!(deleted_at: Time.current)

    get "/api/v1/likes/incoming", headers: bearer_headers(@token)

    assert_response :success
    assert_empty JSON.parse(response.body).fetch("likes")
  end

  test "incoming never leaks another brand's like data" do
    other_brand = Brand.create!(slug: "date9ja", name: "Date9ja")
    BrandDomain.create!(brand: other_brand, host: "date9ja.test")
    cross_brand_viewer = create_profile(brand: other_brand, gender: "woman", interested_in: [ "man" ])
    cross_brand_liker = create_profile(brand: other_brand, gender: "man", interested_in: [ "woman" ])
    create_like(cross_brand_liker, cross_brand_viewer)

    get "/api/v1/likes/incoming", headers: bearer_headers(@token)

    assert_response :success
    assert_empty JSON.parse(response.body).fetch("likes")
  end

  test "incoming paginates with a stable cursor" do
    likers = 3.times.map { create_profile(gender: "man", interested_in: [ "woman" ]) }
    likes = likers.map { |liker| create_like(liker, @viewer) }
    likes.each_with_index { |like, index| like.update_columns(created_at: Time.utc(2026, 8, 13, 12, 0, index)) }

    get "/api/v1/likes/incoming", headers: bearer_headers(@token), params: { limit: 2 }
    first_page = JSON.parse(response.body)

    assert_response :success
    assert_equal [ likers[2].public_id, likers[1].public_id ],
      first_page.fetch("likes").pluck("profile").pluck("id")
    assert first_page.fetch("next_cursor").present?

    get "/api/v1/likes/incoming",
      headers: bearer_headers(@token),
      params: { limit: 2, cursor: first_page.fetch("next_cursor") }
    second_page = JSON.parse(response.body)

    assert_response :success
    assert_equal [ likers[0].public_id ], second_page.fetch("likes").pluck("profile").pluck("id")
    assert_nil second_page.fetch("next_cursor")
  end

  test "incoming rejects a cursor minted for the outgoing endpoint" do
    other = create_profile(gender: "man", interested_in: [ "woman" ])
    create_like(other, @viewer)
    outgoing_cursor = Matching::LikesCursor.encode(
      brand: @brand, viewer: @viewer, direction: "outgoing", created_at: Time.current, counterpart: other
    )

    get "/api/v1/likes/incoming", headers: bearer_headers(@token), params: { cursor: outgoing_cursor }

    assert_response :unprocessable_entity
    assert_equal "invalid_cursor", JSON.parse(response.body).fetch("error")
  end

  # -- GET /api/v1/likes/outgoing ------------------------------------------

  test "outgoing requires authentication" do
    get "/api/v1/likes/outgoing"

    assert_response :unauthorized
  end

  test "outgoing lists profiles the viewer has liked, newest first" do
    older = create_profile(gender: "man", interested_in: [ "woman" ], display_name: "Older")
    newer = create_profile(gender: "man", interested_in: [ "woman" ], display_name: "Newer")
    like_older = create_like(@viewer, older)
    like_older.update_columns(created_at: 2.days.ago)
    create_like(@viewer, newer)

    get "/api/v1/likes/outgoing", headers: bearer_headers(@token)

    assert_response :success
    payload = JSON.parse(response.body).fetch("likes")
    assert_equal [ "Newer", "Older" ], payload.pluck("profile").pluck("display_name")
  end

  test "outgoing excludes a pair with an active match" do
    other = create_profile(gender: "man", interested_in: [ "woman" ])
    create_like(@viewer, other)
    create_match(@viewer, other)

    get "/api/v1/likes/outgoing", headers: bearer_headers(@token)

    assert_response :success
    assert_empty JSON.parse(response.body).fetch("likes")
  end

  test "outgoing excludes either direction of block" do
    liked = create_profile(gender: "man", interested_in: [ "woman" ])
    create_like(@viewer, liked)
    create_block(blocker: liked, blocked: @viewer)

    get "/api/v1/likes/outgoing", headers: bearer_headers(@token)

    assert_response :success
    assert_empty JSON.parse(response.body).fetch("likes")
  end

  test "outgoing excludes a suspended or closed recipient" do
    suspended = create_profile(gender: "man", interested_in: [ "woman" ])
    create_like(@viewer, suspended)
    suspended.update!(status: :suspended)

    closed = create_profile(gender: "man", interested_in: [ "woman" ])
    create_like(@viewer, closed)
    closed.user.update!(status: :closed)

    get "/api/v1/likes/outgoing", headers: bearer_headers(@token)

    assert_response :success
    assert_empty JSON.parse(response.body).fetch("likes")
  end

  test "outgoing excludes a discarded like" do
    liked = create_profile(gender: "man", interested_in: [ "woman" ])
    like = create_like(@viewer, liked)
    like.update!(deleted_at: Time.current)

    get "/api/v1/likes/outgoing", headers: bearer_headers(@token)

    assert_response :success
    assert_empty JSON.parse(response.body).fetch("likes")
  end

  test "outgoing never leaks another brand's like data" do
    other_brand = Brand.create!(slug: "date9ja", name: "Date9ja")
    BrandDomain.create!(brand: other_brand, host: "date9ja.test")
    cross_brand_viewer = create_profile(brand: other_brand, gender: "woman", interested_in: [ "man" ])
    cross_brand_liked = create_profile(brand: other_brand, gender: "man", interested_in: [ "woman" ])
    create_like(cross_brand_viewer, cross_brand_liked)

    get "/api/v1/likes/outgoing", headers: bearer_headers(@token)

    assert_response :success
    assert_empty JSON.parse(response.body).fetch("likes")
  end

  test "outgoing paginates with a stable cursor" do
    liked_profiles = 3.times.map { create_profile(gender: "man", interested_in: [ "woman" ]) }
    likes = liked_profiles.map { |liked| create_like(@viewer, liked) }
    likes.each_with_index { |like, index| like.update_columns(created_at: Time.utc(2026, 8, 13, 12, 0, index)) }

    get "/api/v1/likes/outgoing", headers: bearer_headers(@token), params: { limit: 2 }
    first_page = JSON.parse(response.body)

    assert_response :success
    assert_equal [ liked_profiles[2].public_id, liked_profiles[1].public_id ],
      first_page.fetch("likes").pluck("profile").pluck("id")

    get "/api/v1/likes/outgoing",
      headers: bearer_headers(@token),
      params: { limit: 2, cursor: first_page.fetch("next_cursor") }
    second_page = JSON.parse(response.body)

    assert_response :success
    assert_equal [ liked_profiles[0].public_id ], second_page.fetch("likes").pluck("profile").pluck("id")
  end

  test "rejects invalid cursors and limits on both directions" do
    get "/api/v1/likes/incoming", headers: bearer_headers(@token), params: { cursor: "invalid" }
    assert_response :unprocessable_entity
    assert_equal "invalid_cursor", JSON.parse(response.body).fetch("error")

    get "/api/v1/likes/incoming", headers: bearer_headers(@token), params: { limit: 51 }
    assert_response :unprocessable_entity
    assert_equal "invalid_limit", JSON.parse(response.body).fetch("error")

    get "/api/v1/likes/outgoing", headers: bearer_headers(@token), params: { cursor: "invalid" }
    assert_response :unprocessable_entity
    assert_equal "invalid_cursor", JSON.parse(response.body).fetch("error")

    get "/api/v1/likes/outgoing", headers: bearer_headers(@token), params: { limit: 51 }
    assert_response :unprocessable_entity
    assert_equal "invalid_limit", JSON.parse(response.body).fetch("error")
  end

  # -- State transitions -----------------------------------------------------

  test "a mutual like creates a match and disappears from both like surfaces, appearing in matches" do
    other = create_profile(gender: "man", interested_in: [ "woman" ])
    create_like(other, @viewer)

    assert_difference -> { Match.count }, 1 do
      post "/api/v1/profiles/#{other.public_id}/likes", headers: bearer_headers(@token)
    end

    assert_response :created

    get "/api/v1/likes/incoming", headers: bearer_headers(@token)
    assert_empty JSON.parse(response.body).fetch("likes")

    get "/api/v1/likes/outgoing", headers: bearer_headers(@token)
    assert_empty JSON.parse(response.body).fetch("likes")

    get "/api/v1/matches", headers: bearer_headers(@token)
    assert_equal other.public_id, JSON.parse(response.body).fetch("matches").sole.fetch("profile").fetch("id")
  end

  test "blocking a liker removes them from the incoming surface immediately" do
    liker = create_profile(gender: "man", interested_in: [ "woman" ])
    create_like(liker, @viewer)

    get "/api/v1/likes/incoming", headers: bearer_headers(@token)
    assert_equal 1, JSON.parse(response.body).fetch("likes").size

    post "/api/v1/profiles/#{liker.public_id}/block", headers: bearer_headers(@token)
    assert_response :success

    get "/api/v1/likes/incoming", headers: bearer_headers(@token)
    assert_empty JSON.parse(response.body).fetch("likes")
  end

  test "HookUs incoming likes never include a compatibility field" do
    liker = create_profile(gender: "man", interested_in: [ "woman" ])
    create_like(liker, @viewer)

    get "/api/v1/likes/incoming", headers: bearer_headers(@token)

    profile = JSON.parse(response.body).fetch("likes").sole.fetch("profile")
    assert_not profile.key?("compatibility")
  end

  test "DateZA incoming and outgoing likes include the dateza_v1 compatibility field" do
    brand = Brand.create!(slug: "dateza", name: "DateZA")
    BrandDomain.create!(brand:, host: "dateza.test")
    viewer = create_profile(brand:, gender: "woman", interested_in: [ "man" ])
    liker = create_profile(brand:, gender: "man", interested_in: [ "woman" ])
    liked = create_profile(brand:, gender: "man", interested_in: [ "woman" ])
    create_like(liker, viewer)
    create_like(viewer, liked)
    identifier = IdentityIdentifier.create!(
      user: viewer.user, kind: :email, normalized_value: "viewer@example.com", verified_at: Time.current
    )
    credential = Credential.create!(user: viewer.user, identity_identifier: identifier, kind: :password, status: :active)
    token, = Session.issue!(brand:, user: viewer.user, credential:)
    host! "dateza.test"

    get "/api/v1/likes/incoming", headers: bearer_headers(token)
    incoming_profile = JSON.parse(response.body).fetch("likes").sole.fetch("profile")
    assert incoming_profile.key?("compatibility")

    get "/api/v1/likes/outgoing", headers: bearer_headers(token)
    outgoing_profile = JSON.parse(response.body).fetch("likes").sole.fetch("profile")
    assert outgoing_profile.key?("compatibility")
  end

  private

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end

  def create_profile(brand: @brand, gender:, interested_in:, display_name: nil)
    user = User.create!
    membership = BrandMembership.create!(brand:, user:)
    profile = Profile.create!(
      brand:, user:, brand_membership: membership, gender:, birthdate: 30.years.ago.to_date,
      status: :active, visibility: :visible, display_name:
    )
    ProfilePreference.create!(
      brand:, user:, profile:, min_age: 25, max_age: 40, interested_in:
    )
    profile
  end

  def create_like(liker, liked)
    Like.create!(brand: liker.brand, liker_profile: liker, liked_profile: liked, kind: :like)
  end

  def create_match(first, second)
    profile_a_id, profile_b_id = Match.canonical_pair(first.id, second.id)
    Match.create!(brand: @brand, profile_a_id:, profile_b_id:)
  end

  def create_block(blocker:, blocked:)
    ProfileBlock.create!(brand: blocker.brand, blocker_profile: blocker, blocked_profile: blocked)
  end
end
