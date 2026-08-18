require "test_helper"
require_relative "../../../support/hook_test_helpers"

class Api::V1::HooksControllerTest < ActionDispatch::IntegrationTest
  include HookTestHelpers

  setup do
    @brand = Brand.create!(slug: "hookus", name: "HookUs")
    BrandDomain.create!(brand: @brand, host: "hookus.test")
    @sender = create_member(brand: @brand)
    @recipient = create_member(brand: @brand)
    @sender_token, = Session.issue!(brand: @brand, user: @sender.user)
    @recipient_token, = Session.issue!(brand: @brand, user: @recipient.user)
    host! "hookus.test"
  end

  def auth(token)
    { "Authorization" => "Bearer #{token}" }
  end

  test "requires authentication to send a hook" do
    post "/api/v1/profiles/#{@recipient.public_id}/hook", params: { message: "hi" }
    assert_response :unauthorized
  end

  test "sends a hook and returns a minimal pending acknowledgement" do
    post "/api/v1/profiles/#{@recipient.public_id}/hook",
      headers: auth(@sender_token), params: { message: "You're my vibe 🔥" }

    assert_response :created
    body = JSON.parse(response.body).fetch("hook")
    assert_equal "pending", body.fetch("status")
    assert body.fetch("expires_at").present?
    # The sender ack never leaks recipient-side detail.
    assert_not body.key?("message")
    assert_not body.key?("sender")
  end

  test "rejects a blank message" do
    post "/api/v1/profiles/#{@recipient.public_id}/hook",
      headers: auth(@sender_token), params: { message: "   " }

    assert_response :unprocessable_entity
    assert_equal "message_blank", JSON.parse(response.body).fetch("error")
  end

  test "the sender cannot send a second opener before a reply" do
    post "/api/v1/profiles/#{@recipient.public_id}/hook", headers: auth(@sender_token), params: { message: "first" }
    assert_response :created

    post "/api/v1/profiles/#{@recipient.public_id}/hook", headers: auth(@sender_token), params: { message: "second" }
    assert_response :conflict
    assert_equal "already_hooked", JSON.parse(response.body).fetch("error")

    # And there is no conversation to smuggle a second message through.
    assert_equal 0, Conversation.where(brand: @brand).count
  end

  test "full loop: recipient reply unlocks a two-way conversation" do
    post "/api/v1/profiles/#{@recipient.public_id}/hook", headers: auth(@sender_token), params: { message: "opener 🔥" }
    hook = Hook.find_by!(brand: @brand, sender_profile: @sender, recipient_profile: @recipient)

    post "/api/v1/hooks/#{hook.public_id}/reply", headers: auth(@recipient_token), params: { message: "hey!" }
    assert_response :created
    reply_body = JSON.parse(response.body)
    conversation_id = reply_body.fetch("conversation").fetch("id")
    assert_equal "hey!", reply_body.fetch("message").fetch("body")

    # Sender can now message through the ordinary conversation endpoint.
    post "/api/v1/conversations/#{conversation_id}/messages", headers: auth(@sender_token), params: { body: "when?" }
    assert_response :created

    get "/api/v1/conversations/#{conversation_id}/messages", headers: auth(@sender_token)
    bodies = JSON.parse(response.body).fetch("messages").pluck("body")
    assert_includes bodies, "opener 🔥"
    assert_includes bodies, "hey!"
    assert_includes bodies, "when?"
  end

  test "recipient inbox shows the opener and sender profile; others cannot see it" do
    post "/api/v1/profiles/#{@recipient.public_id}/hook", headers: auth(@sender_token), params: { message: "secret opener" }

    get "/api/v1/hooks", headers: auth(@recipient_token)
    assert_response :success
    hooks = JSON.parse(response.body).fetch("hooks")
    assert_equal 1, hooks.length
    assert_equal "secret opener", hooks.first.fetch("message")
    assert_equal @sender.public_id, hooks.first.fetch("sender").fetch("id")

    # The sender has no inbox entry for a hook they sent; it is private to the recipient.
    get "/api/v1/hooks", headers: auth(@sender_token)
    assert_response :success
    assert_equal 0, JSON.parse(response.body).fetch("hooks").length
  end

  test "recipient can decline and the sender cannot re-hook" do
    post "/api/v1/profiles/#{@recipient.public_id}/hook", headers: auth(@sender_token), params: { message: "opener" }
    hook = Hook.find_by!(brand: @brand, sender_profile: @sender)

    post "/api/v1/hooks/#{hook.public_id}/decline", headers: auth(@recipient_token)
    assert_response :no_content

    post "/api/v1/profiles/#{@recipient.public_id}/hook", headers: auth(@sender_token), params: { message: "again" }
    assert_response :conflict
  end

  test "declining someone else's hook is a neutral 404" do
    post "/api/v1/profiles/#{@recipient.public_id}/hook", headers: auth(@sender_token), params: { message: "opener" }
    hook = Hook.find_by!(brand: @brand, sender_profile: @sender)
    stranger_token, = Session.issue!(brand: @brand, user: create_member(brand: @brand).user)

    post "/api/v1/hooks/#{hook.public_id}/decline", headers: auth(stranger_token)
    assert_response :not_found
    assert_equal "hook_unavailable", JSON.parse(response.body).fetch("error")
  end

  test "enforces the daily hook limit with a 429 and Retry-After" do
    Hooks::Policy::FREE_DAILY_LIMIT.times do
      target = create_member(brand: @brand)
      post "/api/v1/profiles/#{target.public_id}/hook", headers: auth(@sender_token), params: { message: "hi" }
      assert_response :created
    end

    target = create_member(brand: @brand)
    post "/api/v1/profiles/#{target.public_id}/hook", headers: auth(@sender_token), params: { message: "one more" }
    assert_response :too_many_requests
    assert_equal "hook_rate_limited", JSON.parse(response.body).fetch("error")
    assert response.headers["Retry-After"].present?
  end
end
