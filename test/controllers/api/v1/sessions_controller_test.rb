require "test_helper"

class Api::V1::SessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @brand = Brand.create!(slug: "hookus", name: "HookUs")
    BrandDomain.create!(brand: @brand, host: "hookus.test")
    @user = User.create!
    BrandMembership.create!(brand: @brand, user: @user)
    @token, @session = Session.issue!(brand: @brand, user: @user, device_name: "Test device")
    host! "hookus.test"
  end

  test "lists the member's own active sessions for this brand, newest-active first" do
    _other_token, other_session = Session.issue!(brand: @brand, user: @user)
    other_session.update!(last_used_at: 1.day.ago)

    get "/api/v1/sessions", headers: bearer_headers(@token)

    assert_response :success
    sessions = JSON.parse(response.body).fetch("sessions")
    ids = sessions.map { |s| s.fetch("id") }
    assert_equal [ @session.id, other_session.id ], ids
    current = sessions.find { |s| s.fetch("id") == @session.id }
    assert current.fetch("current")
    assert_equal "Test device", current.fetch("device_name")
    refute sessions.find { |s| s.fetch("id") == other_session.id }.fetch("current")
  end

  test "does not list another user's sessions or another brand's sessions" do
    other_user = User.create!
    BrandMembership.create!(brand: @brand, user: other_user)
    _, other_user_session = Session.issue!(brand: @brand, user: other_user)

    other_brand = Brand.create!(slug: "date9ja", name: "Date9ja")
    BrandMembership.create!(brand: other_brand, user: @user)
    _, other_brand_session = Session.issue!(brand: other_brand, user: @user)

    get "/api/v1/sessions", headers: bearer_headers(@token)

    ids = JSON.parse(response.body).fetch("sessions").map { |s| s.fetch("id") }
    assert_not_includes ids, other_user_session.id
    assert_not_includes ids, other_brand_session.id
  end

  test "revokes a different active session and audits it" do
    _other_token, other_session = Session.issue!(brand: @brand, user: @user)

    assert_difference -> { SecurityEvent.where(event_type: "auth.session.revoked").count }, 1 do
      delete "/api/v1/sessions/#{other_session.id}", headers: bearer_headers(@token)
    end

    assert_response :no_content
    assert other_session.reload.revoked?
    assert_not @session.reload.revoked?
  end

  test "refuses to revoke the caller's own current session through this endpoint" do
    delete "/api/v1/sessions/#{@session.id}", headers: bearer_headers(@token)

    assert_response :conflict
    assert_not @session.reload.revoked?
  end

  test "404s for a session id that does not belong to the caller" do
    other_user = User.create!
    BrandMembership.create!(brand: @brand, user: other_user)
    _, other_user_session = Session.issue!(brand: @brand, user: other_user)

    delete "/api/v1/sessions/#{other_user_session.id}", headers: bearer_headers(@token)

    assert_response :not_found
    assert_not other_user_session.reload.revoked?
  end

  test "requires authentication" do
    get "/api/v1/sessions"
    assert_response :unauthorized

    delete "/api/v1/sessions/#{@session.id}"
    assert_response :unauthorized
  end

  private

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end
end
