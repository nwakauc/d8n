require "test_helper"

class Api::V1::Auth::SessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @brand = Brand.create!(slug: "hookus", name: "HookUs")
    BrandDomain.create!(brand: @brand, host: "hookus.test")
    @user = User.create!
    BrandMembership.create!(brand: @brand, user: @user)
    @token, @session = Session.issue!(brand: @brand, user: @user)
    host! "hookus.test"
  end

  test "revokes the current brand session and audits the logout" do
    assert_difference -> { SecurityEvent.where(event_type: "auth.session.revoked").count }, 1 do
      delete "/api/v1/auth/session", headers: bearer_headers(@token)
    end

    assert_response :no_content
    assert @session.reload.revoked?
    event = SecurityEvent.find_by!(event_type: "auth.session.revoked")
    assert_equal @brand, event.brand
    assert_equal @user, event.user
    assert_equal @session.id, event.metadata.fetch("session_id")
  end

  test "does not revoke another session for the same identity" do
    other_brand = Brand.create!(slug: "date9ja", name: "Date9ja")
    BrandMembership.create!(brand: other_brand, user: @user)
    _, other_session = Session.issue!(brand: other_brand, user: @user)

    delete "/api/v1/auth/session", headers: bearer_headers(@token)

    assert_response :no_content
    assert_not other_session.reload.revoked?
  end

  test "requires authentication" do
    delete "/api/v1/auth/session"

    assert_response :unauthorized
    assert_not @session.reload.revoked?
  end

  private

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end
end
