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

  private

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end

  def create_profile(brand: @brand, gender:, interested_in:)
    user = User.create!
    membership = BrandMembership.create!(brand:, user:)
    profile = Profile.create!(
      brand:, user:, brand_membership: membership, gender:, birthdate: 30.years.ago.to_date,
      status: :active, visibility: :visible
    )
    ProfilePreference.create!(
      brand:, user:, profile:, min_age: 25, max_age: 40, interested_in:
    )
    profile
  end
end
