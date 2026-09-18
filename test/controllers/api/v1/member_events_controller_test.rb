require "test_helper"

class Api::V1::MemberEventsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @brand = Brand.create!(slug: "hookus", name: "HookUs")
    BrandDomain.create!(brand: @brand, host: "hookus.test")
    @user = User.create!
    BrandMembership.create!(brand: @brand, user: @user)
    @token, = Session.issue!(brand: @brand, user: @user)
    host! "hookus.test"
  end

  test "rejects unauthenticated and foreign origin streams" do
    get "/api/v1/member_events"
    assert_response :unauthorized
    get "/api/v1/member_events", headers: { "Authorization" => "Bearer #{@token}", "Origin" => "https://foreign.test" }
    assert_response :forbidden
  end

  test "subscribes before ready, has private streaming headers and closes on invalid session" do
    stub_method(Realtime::MemberEvents, :session_active?, ->(**) { false }) do
      get "/api/v1/member_events", headers: { "Authorization" => "Bearer #{@token}" }
      assert_response :success
      assert_equal "text/event-stream", response.media_type
      assert_equal "private, no-store", response.headers["Cache-Control"]
      assert_includes response.body, "event: ready"
    end
  end
  test "streams a committed recipient hint without buffering until connection close" do
    unsubscribed = false
    adapter = Object.new
    adapter.define_singleton_method(:subscribe) do |_channel, callback, ready|
      ready.call
      callback.call({ type: "read_state_changed" }.to_json)
    end
    adapter.define_singleton_method(:unsubscribe) { |*| unsubscribed = true }
    checks = 0
    stub_method(ActionCable.server, :pubsub, -> { adapter }) do
      stub_method(Realtime::MemberEvents, :session_active?, ->(**) { checks += 1; checks <= 2 }) do
        get "/api/v1/member_events", headers: { "Authorization" => "Bearer #{@token}" }
        assert_includes response.body, "event: member"
        assert_includes response.body, '"type":"read_state_changed"'
      end
    end
    assert unsubscribed
  end
end
