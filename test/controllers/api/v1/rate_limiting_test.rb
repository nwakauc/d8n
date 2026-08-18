require "test_helper"
require_relative "../../../support/hook_test_helpers"

# End-to-end HTTP contract for the generic abuse-protection layer: exceeding an
# action's burst ceiling yields a standardised 429 (`rate_limited`) with a
# Retry-After header, counters are per-user (one member being throttled never
# throttles another), and the guarded write never runs once throttled. Each test
# drives just past the smallest (burst) rule for that surface.
#
# The request loops run inside `freeze_time` so every request falls in one
# fixed window bucket — otherwise a burst that straddled a real 10-second
# boundary could split across two buckets and never trip, making the suite flaky.
class Api::V1::RateLimitingTest < ActionDispatch::IntegrationTest
  include HookTestHelpers

  setup do
    @brand = Brand.create!(slug: "hookus", name: "HookUs")
    BrandDomain.create!(brand: @brand, host: "hookus.test")
    host! "hookus.test"
  end

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end

  def burst_limit(action)
    AbuseProtection::Policy.rules_for(action).first.limit
  end

  # --- Discovery (read scraping) -------------------------------------------

  test "discovery throttles after the burst ceiling with a Retry-After header" do
    member = create_member(brand: @brand)
    token, = Session.issue!(brand: @brand, user: member.user)

    freeze_time do
      burst_limit(:discovery).times do
        get "/api/v1/discovery", headers: bearer_headers(token)
        assert_response :success
      end

      get "/api/v1/discovery", headers: bearer_headers(token)
      assert_response :too_many_requests
      assert_equal "rate_limited", JSON.parse(response.body).fetch("error")
      assert response.headers["Retry-After"].to_i.positive?
    end
  end

  test "discovery counters are not shared between members" do
    a = create_member(brand: @brand)
    b = create_member(brand: @brand)
    token_a, = Session.issue!(brand: @brand, user: a.user)
    token_b, = Session.issue!(brand: @brand, user: b.user)

    freeze_time do
      (burst_limit(:discovery) + 1).times { get "/api/v1/discovery", headers: bearer_headers(token_a) }
      assert_response :too_many_requests

      get "/api/v1/discovery", headers: bearer_headers(token_b)
      assert_response :success
    end
  end

  # --- Reporting (safety write, must stay controlled) ----------------------

  test "reporting throttles with a controlled 429 rather than silently dropping" do
    reporter = create_member(brand: @brand)
    target = create_member(brand: @brand)
    token, = Session.issue!(brand: @brand, user: reporter.user)

    freeze_time do
      burst_limit(:report_profile).times do
        post "/api/v1/profiles/#{target.public_id}/report",
          params: { reason: "spam" }, headers: bearer_headers(token)
        assert_includes [ 200, 201 ], response.status
      end

      post "/api/v1/profiles/#{target.public_id}/report",
        params: { reason: "spam" }, headers: bearer_headers(token)
      assert_response :too_many_requests
      assert_equal "rate_limited", JSON.parse(response.body).fetch("error")
    end
  end

  # --- Messaging (rate-limits the send action, not reads) ------------------

  test "messaging send throttles after the burst ceiling" do
    a = create_member(brand: @brand)
    b = create_member(brand: @brand)
    conversation = matched_conversation(a, b)
    token, = Session.issue!(brand: @brand, user: a.user)

    freeze_time do
      burst_limit(:send_message).times do |i|
        post "/api/v1/conversations/#{conversation.public_id}/messages",
          params: { body: "hi #{i}" }, headers: bearer_headers(token)
        assert_response :created
      end

      post "/api/v1/conversations/#{conversation.public_id}/messages",
        params: { body: "one too many" }, headers: bearer_headers(token)
      assert_response :too_many_requests
    end
  end

  test "reading messages is never throttled by the send limit" do
    a = create_member(brand: @brand)
    b = create_member(brand: @brand)
    conversation = matched_conversation(a, b)
    token, = Session.issue!(brand: @brand, user: a.user)

    freeze_time do
      (burst_limit(:send_message) + 5).times do
        get "/api/v1/conversations/#{conversation.public_id}/messages", headers: bearer_headers(token)
        assert_response :success
      end
    end
  end

  # --- Profile writes share one bucket across surfaces ---------------------

  test "profile mutation endpoints share the profile_write bucket" do
    member = create_member(brand: @brand)
    token, = Session.issue!(brand: @brand, user: member.user)
    limit = burst_limit(:profile_write)

    freeze_time do
      # Split the budget across two different profile-write endpoints; because
      # they share one counter, their combined volume trips the shared limit.
      (limit / 2).times do
        patch "/api/v1/profile", params: { display_name: "Ada" }, headers: bearer_headers(token)
        assert_response :ok
      end
      (limit - (limit / 2)).times do
        patch "/api/v1/profile/preferences", params: { min_age: 18, max_age: 40 }, headers: bearer_headers(token)
        assert_response :ok
      end

      patch "/api/v1/profile", params: { display_name: "Grace" }, headers: bearer_headers(token)
      assert_response :too_many_requests
    end
  end

  # --- Hook Tonight activation ---------------------------------------------

  test "hook tonight activation throttles request flooding without changing semantics" do
    member = create_member(brand: @brand)
    token, = Session.issue!(brand: @brand, user: member.user)

    freeze_time do
      burst_limit(:hook_tonight_activation).times do
        post "/api/v1/hook_tonight", headers: bearer_headers(token)
        assert_response :created
      end

      post "/api/v1/hook_tonight", headers: bearer_headers(token)
      assert_response :too_many_requests
    end

    # The existing availability state is untouched by a throttled request.
    assert HookTonightState.live.exists?(brand: @brand, profile: member)
  end

  # --- Hook is NOT governed by the generic layer ---------------------------

  test "hook sending keeps its distinct domain rate-limit code, not the generic one" do
    sender = create_member(brand: @brand)
    token, = Session.issue!(brand: @brand, user: sender.user)

    # Exhaust the product Hook allowance (Hooks::Policy), each to a fresh target.
    Hooks::Policy::FREE_DAILY_LIMIT.times do
      target = create_member(brand: @brand)
      post "/api/v1/profiles/#{target.public_id}/hook",
        params: { message: "hey there, you're my vibe 🔥" }, headers: bearer_headers(token)
      assert_response :created
    end

    target = create_member(brand: @brand)
    post "/api/v1/profiles/#{target.public_id}/hook",
      params: { message: "one more 🔥" }, headers: bearer_headers(token)
    assert_response :too_many_requests
    assert_equal "hook_rate_limited", JSON.parse(response.body).fetch("error")
  end

  private

  # Builds an active match + conversation between two members (a likes b, b likes
  # a) and returns the conversation.
  def matched_conversation(sender, other)
    Like.create!(brand: @brand, liker_profile: other, liked_profile: sender)
    match = Matching::LikeProfile.call(
      user: sender.user, brand: @brand, target_public_id: other.public_id,
      strategy: Matching::Strategies::Hookus
    ).match
    Messaging::StartConversation.call(
      user: sender.user, brand: @brand, match_public_id: match.public_id
    ).conversation
  end
end
