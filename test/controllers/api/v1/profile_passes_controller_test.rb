require "test_helper"

class Api::V1::ProfilePassesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @brand = Brand.create!(slug: "hookus", name: "HookUs")
    BrandDomain.create!(brand: @brand, host: "hookus.test")
    @viewer = create_profile(gender: "woman", interested_in: [ "man" ])
    @candidate = create_profile(gender: "man", interested_in: [ "woman" ])
    @token, = Session.issue!(brand: @brand, user: @viewer.user)
    host! "hookus.test"
  end

  test "creates an idempotent pass" do
    assert_difference -> { ProfilePass.count }, 1 do
      post "/api/v1/profiles/#{@candidate.public_id}/pass", headers: bearer_headers(@token)
    end
    assert_response :created
    assert_equal true, JSON.parse(response.body).fetch("created")

    assert_no_difference -> { ProfilePass.count } do
      post "/api/v1/profiles/#{@candidate.public_id}/pass", headers: bearer_headers(@token)
    end
    assert_response :success
    assert_equal false, JSON.parse(response.body).fetch("created")
  end

  test "rejects a pass after a positive interaction" do
    Like.create!(brand: @brand, liker_profile: @viewer, liked_profile: @candidate)

    post "/api/v1/profiles/#{@candidate.public_id}/pass", headers: bearer_headers(@token)

    assert_response :conflict
    assert_equal "already_liked", JSON.parse(response.body).fetch("error")
  end

  test "does not reveal unavailable targets" do
    @candidate.update!(visibility: :hidden)

    post "/api/v1/profiles/#{@candidate.public_id}/pass", headers: bearer_headers(@token)

    assert_response :not_found
    assert_equal "profile_unavailable", JSON.parse(response.body).fetch("error")
  end

  private

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end

  def create_profile(gender:, interested_in:)
    user = User.create!
    membership = BrandMembership.create!(brand: @brand, user:)
    profile = Profile.create!(
      brand: @brand, user:, brand_membership: membership, gender:, birthdate: 30.years.ago.to_date,
      status: :active, visibility: :visible
    )
    ProfilePreference.create!(
      brand: @brand, user:, profile:, min_age: 25, max_age: 40, interested_in:
    )
    profile
  end
end
