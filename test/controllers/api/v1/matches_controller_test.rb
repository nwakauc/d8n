require "test_helper"

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

  test "rejects invalid cursors and limits" do
    get "/api/v1/matches", headers: bearer_headers(@token), params: { cursor: "invalid" }
    assert_response :unprocessable_entity
    assert_equal "invalid_cursor", JSON.parse(response.body).fetch("error")

    get "/api/v1/matches", headers: bearer_headers(@token), params: { limit: 51 }
    assert_response :unprocessable_entity
    assert_equal "invalid_limit", JSON.parse(response.body).fetch("error")
  end

  private

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end

  def create_profile(gender:, interested_in:, display_name: nil)
    user = User.create!
    membership = BrandMembership.create!(brand: @brand, user:)
    profile = Profile.create!(
      brand: @brand, user:, brand_membership: membership, display_name:, gender:,
      birthdate: 30.years.ago.to_date, status: :active, visibility: :visible
    )
    ProfilePreference.create!(
      brand: @brand, user:, profile:, min_age: 25, max_age: 40, interested_in:
    )
    profile
  end

  def create_match(first, second)
    profile_a_id, profile_b_id = Match.canonical_pair(first.id, second.id)
    Match.create!(brand: @brand, profile_a_id:, profile_b_id:)
  end
end
