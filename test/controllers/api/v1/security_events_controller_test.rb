require "test_helper"

class Api::V1::SecurityEventsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @brand = Brand.create!(slug: "hookus", name: "HookUs")
    BrandDomain.create!(brand: @brand, host: "hookus.test")
    @user = User.create!
    BrandMembership.create!(brand: @brand, user: @user)
    @token, = Session.issue!(brand: @brand, user: @user)
    host! "hookus.test"
  end

  test "lists the member's own auth/account events, newest first, without metadata" do
    older = SecurityEvent.create!(brand: @brand, user: @user, event_type: "auth.password.changed", ip_address: "1.2.3.4", metadata: { secret: "internal" })
    older.update_column(:created_at, 2.days.ago)
    newer = SecurityEvent.create!(brand: @brand, user: @user, event_type: "account.deactivated")

    get "/api/v1/security/events", headers: bearer_headers(@token)

    assert_response :success
    events = JSON.parse(response.body).fetch("events")
    assert_equal [ newer.id, older.id ], events.map { |e| e.fetch("id") }
    assert_equal "account.deactivated", events.first.fetch("event_type")
    assert_equal "1.2.3.4", events.last.fetch("ip_address")
    events.each { |e| assert_not e.key?("metadata") }
  end

  test "excludes non-auth/account event types (e.g. moderation) and other users'/brands' events" do
    SecurityEvent.create!(brand: @brand, user: @user, event_type: "trust.report_filed")

    other_user = User.create!
    BrandMembership.create!(brand: @brand, user: other_user)
    SecurityEvent.create!(brand: @brand, user: other_user, event_type: "auth.password.changed")

    other_brand = Brand.create!(slug: "date9ja", name: "Date9ja")
    BrandMembership.create!(brand: other_brand, user: @user)
    SecurityEvent.create!(brand: other_brand, user: @user, event_type: "auth.password.changed")

    get "/api/v1/security/events", headers: bearer_headers(@token)

    assert_empty JSON.parse(response.body).fetch("events")
  end

  test "requires authentication" do
    get "/api/v1/security/events"
    assert_response :unauthorized
  end

  private

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end
end
