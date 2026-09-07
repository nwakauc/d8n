require "test_helper"

class Api::V1::Date9jaCoreDatingLoopTest < ActionDispatch::IntegrationTest
  setup do
    @brand = Brands::Date9jaInstaller.call(hosts: [ "date9ja.test" ])
    @alice = create_profile(
      brand: @brand, gender: "woman", interested_in: [ "man" ], age: 30,
      min_age: 25, max_age: 40
    )
    @bob = create_profile(
      brand: @brand, gender: "man", interested_in: [ "woman" ], age: 32,
      min_age: 25, max_age: 40
    )
    @alice_token, = Session.issue!(brand: @brand, user: @alice.user)
    @bob_token, = Session.issue!(brand: @brand, user: @bob.user)
    host! "date9ja.test"
  end

  test "Date9ja discovers, likes, matches, chats, and exchanges a reply" do
    get "/api/v1/discovery", headers: bearer_headers(@alice_token)
    assert_response :success
    assert_includes JSON.parse(response.body).fetch("profiles").pluck("id"), @bob.public_id

    post "/api/v1/profiles/#{@bob.public_id}/likes", headers: bearer_headers(@alice_token)
    assert_response :created
    assert_equal false, JSON.parse(response.body).fetch("matched")

    get "/api/v1/discovery", headers: bearer_headers(@bob_token)
    assert_response :success
    assert_includes JSON.parse(response.body).fetch("profiles").pluck("id"), @alice.public_id

    post "/api/v1/profiles/#{@alice.public_id}/likes", headers: bearer_headers(@bob_token)
    assert_response :created
    payload = JSON.parse(response.body)
    assert payload.fetch("matched")
    match_id = payload.fetch("match_id")

    post "/api/v1/matches/#{match_id}/conversation", headers: bearer_headers(@alice_token)
    assert_response :created
    conversation_id = JSON.parse(response.body).dig("conversation", "id")

    post "/api/v1/conversations/#{conversation_id}/messages",
      headers: bearer_headers(@alice_token), params: { body: "Hello" }
    assert_response :created

    get "/api/v1/conversations/#{conversation_id}/messages", headers: bearer_headers(@bob_token)
    assert_response :success
    assert_equal [ "Hello" ], JSON.parse(response.body).fetch("messages").pluck("body")

    post "/api/v1/conversations/#{conversation_id}/messages",
      headers: bearer_headers(@bob_token), params: { body: "Hi" }
    assert_response :created

    get "/api/v1/conversations/#{conversation_id}/messages", headers: bearer_headers(@alice_token)
    assert_response :success
    assert_equal [ "Hi", "Hello" ], JSON.parse(response.body).fetch("messages").pluck("body")
    assert_equal 1, Match.kept.where(brand: @brand).count
    assert_equal 1, Conversation.kept.where(brand: @brand).count
  end

  private

  def create_profile(brand:, gender:, interested_in:, age:, min_age:, max_age:)
    user = User.create!
    membership = BrandMembership.create!(brand:, user:)
    profile = Profile.create!(
      brand:, user:, brand_membership: membership, display_name: "Member", gender:,
      birthdate: age.years.ago.to_date, status: :active, visibility: :visible
    )
    ProfilePreference.create!(brand:, user:, profile:, min_age:, max_age:, interested_in:)
    profile
  end

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end
end
