require "test_helper"

class Api::V1::MeControllerTest < ActionDispatch::IntegrationTest
  setup do
    @brand = Brand.create!(slug: "hookus", name: "HookUs")
    BrandDomain.create!(brand: @brand, host: "hookus.test")
    @user = User.create!
    @membership = BrandMembership.create!(brand: @brand, user: @user)
    host! "hookus.test"
  end

  test "requires a bearer session" do
    get "/api/v1/me"

    assert_response :unauthorized
    assert_equal({ "error" => "unauthorized" }, JSON.parse(response.body))
  end

  test "returns the current user for a valid bearer session" do
    token, session = Session.issue!(brand: @brand, user: @user)

    get "/api/v1/me", headers: bearer_headers(token)

    assert_response :success
    response_body = JSON.parse(response.body)
    assert_equal @user.id, response_body.fetch("user_id")
    assert_equal "hookus", response_body.fetch("brand").fetch("slug")
    assert_equal session.id, response_body.fetch("session").fetch("id")
    assert Session.find(session.id).last_used_at > session.last_used_at
  end

  test "rejects expired sessions" do
    token, session = Session.issue!(brand: @brand, user: @user)
    session.update!(expires_at: 1.minute.ago)

    get "/api/v1/me", headers: bearer_headers(token)

    assert_response :unauthorized
  end

  test "rejects revoked sessions" do
    token, session = Session.issue!(brand: @brand, user: @user)
    session.update!(revoked_at: Time.current)

    get "/api/v1/me", headers: bearer_headers(token)

    assert_response :unauthorized
  end

  test "rejects sessions from another brand" do
    other_brand = Brand.create!(slug: "date9ja", name: "Date9ja")
    token, = Session.issue!(brand: other_brand, user: @user)

    get "/api/v1/me", headers: bearer_headers(token)

    assert_response :unauthorized
  end

  test "rejects sessions when the user is not active" do
    token, = Session.issue!(brand: @brand, user: @user)
    @user.update!(status: :suspended)

    get "/api/v1/me", headers: bearer_headers(token)

    assert_response :unauthorized
  end

  test "rejects sessions when the brand membership is not active" do
    token, = Session.issue!(brand: @brand, user: @user)
    @membership.update!(status: :suspended)

    get "/api/v1/me", headers: bearer_headers(token)

    assert_response :unauthorized
  end

  test "rejects a session issued by a revoked credential" do
    identifier = IdentityIdentifier.create!(user: @user, kind: :phone, normalized_value: "+27821234567")
    credential = Credential.create!(user: @user, identity_identifier: identifier, kind: :phone_otp)
    token, = Session.issue!(brand: @brand, user: @user, credential:)
    credential.update!(status: :revoked)

    get "/api/v1/me", headers: bearer_headers(token)

    assert_response :unauthorized
  end

  private

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end
end
