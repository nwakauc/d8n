require "test_helper"

class Api::V1::ConversationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @brand = Brand.create!(slug: "hookus", name: "HookUs")
    BrandDomain.create!(brand: @brand, host: "hookus.test")
    @viewer = create_profile(brand: @brand, display_name: "Ada")
    @counterpart = create_profile(brand: @brand, display_name: "Sam")
    @match = create_match(@viewer, @counterpart)
    @token, = Session.issue!(brand: @brand, user: @viewer.user)
    host! "hookus.test"
  end

  test "requires authentication" do
    get "/api/v1/conversations"
    assert_response :unauthorized

    post "/api/v1/matches/#{@match.public_id}/conversation"
    assert_response :unauthorized
  end

  test "starts one conversation idempotently with both profile participants" do
    assert_difference -> { Conversation.count }, 1 do
      assert_difference -> { ConversationParticipant.count }, 2 do
        post "/api/v1/matches/#{@match.public_id}/conversation", headers: bearer_headers(@token)
      end
    end

    assert_response :created
    first = JSON.parse(response.body)
    conversation = Conversation.last
    assert first.fetch("created")
    assert_equal conversation.public_id, first.dig("conversation", "id")
    assert_equal @match.public_id, first.dig("conversation", "match_id")
    assert_equal @counterpart.public_id, first.dig("conversation", "profile", "id")
    assert_equal [ @viewer.id, @counterpart.id ].sort,
      conversation.conversation_participants.pluck(:profile_id).sort

    assert_no_difference [ -> { Conversation.count }, -> { ConversationParticipant.count } ] do
      post "/api/v1/matches/#{@match.public_id}/conversation", headers: bearer_headers(@token)
    end

    assert_response :success
    assert_not JSON.parse(response.body).fetch("created")
  end

  test "returns the same not-found response for unknown cross-brand and non-participant matches" do
    outsider_a = create_profile(brand: @brand)
    outsider_b = create_profile(brand: @brand)
    outsider_match = create_match(outsider_a, outsider_b)
    other_brand = Brand.create!(slug: "other", name: "Other")
    other_a = create_profile(brand: other_brand)
    other_b = create_profile(brand: other_brand)
    other_match = create_match(other_a, other_b)

    [ SecureRandom.uuid, outsider_match.public_id, other_match.public_id ].each do |match_id|
      post "/api/v1/matches/#{match_id}/conversation", headers: bearer_headers(@token)
      assert_response :not_found
      assert_equal "conversation_unavailable", JSON.parse(response.body).fetch("error")
    end
  end

  test "does not start a conversation when either participant is unavailable" do
    @counterpart.user.update!(status: :suspended)

    post "/api/v1/matches/#{@match.public_id}/conversation", headers: bearer_headers(@token)

    assert_response :not_found
    assert_equal "conversation_unavailable", JSON.parse(response.body).fetch("error")
    assert_not Conversation.exists?(match: @match)
  end

  test "lists only current participant conversations with public counterpart data" do
    own = start_conversation(@match)
    outsider_a = create_profile(brand: @brand)
    outsider_b = create_profile(brand: @brand)
    outsider = start_conversation(create_match(outsider_a, outsider_b), user: outsider_a.user)
    assert outsider.present?

    get "/api/v1/conversations", headers: bearer_headers(@token)

    assert_response :success
    payload = JSON.parse(response.body).fetch("conversations").sole
    assert_equal own.public_id, payload.fetch("id")
    assert_equal @counterpart.public_id, payload.dig("profile", "id")
    assert_not payload.fetch("profile").key?("birthdate")
    assert_not payload.fetch("profile").key?("user_id")
    assert_not payload.key?("messages")
  end

  test "paginates with a viewer-bound opaque cursor" do
    conversations = 3.times.map do |index|
      counterpart = create_profile(brand: @brand)
      conversation = start_conversation(create_match(@viewer, counterpart))
      conversation.update_columns(created_at: Time.utc(2026, 8, 13, 15, 0, index), updated_at: Time.current)
      conversation
    end

    get "/api/v1/conversations", headers: bearer_headers(@token), params: { limit: 2 }
    first_page = JSON.parse(response.body)

    assert_response :success
    assert_equal [ conversations[2].public_id, conversations[1].public_id ],
      first_page.fetch("conversations").pluck("id")

    get "/api/v1/conversations", headers: bearer_headers(@token),
      params: { limit: 2, cursor: first_page.fetch("next_cursor") }

    assert_response :success
    assert_equal [ conversations[0].public_id ], JSON.parse(response.body).fetch("conversations").pluck("id")
  end

  test "hides conversations after match or participant availability ends" do
    start_conversation(@match)
    @counterpart.brand_membership.update!(status: :suspended)

    get "/api/v1/conversations", headers: bearer_headers(@token)

    assert_response :success
    assert_empty JSON.parse(response.body).fetch("conversations")
  end

  test "retains read-only conversation metadata after a match ends" do
    conversation = start_conversation(@match)
    @match.update!(status: :ended)

    get "/api/v1/conversations", headers: bearer_headers(@token)

    assert_response :success
    assert_equal conversation.public_id,
      JSON.parse(response.body).fetch("conversations").sole.fetch("id")
  end

  test "preloads conversation cards with a bounded query count" do
    start_conversation(@match)
    baseline = count_select_queries do
      get "/api/v1/conversations", headers: bearer_headers(@token)
    end

    4.times do
      counterpart = create_profile(brand: @brand)
      start_conversation(create_match(@viewer, counterpart))
    end
    expanded = count_select_queries do
      get "/api/v1/conversations", headers: bearer_headers(@token)
    end

    assert_response :success
    assert_operator expanded, :<=, baseline + 1
    assert_equal 5, JSON.parse(response.body).fetch("conversations").size
  end

  test "rejects invalid cursors and limits" do
    get "/api/v1/conversations", headers: bearer_headers(@token), params: { cursor: "invalid" }
    assert_response :unprocessable_entity
    assert_equal "invalid_cursor", JSON.parse(response.body).fetch("error")

    get "/api/v1/conversations", headers: bearer_headers(@token), params: { limit: 51 }
    assert_response :unprocessable_entity
    assert_equal "invalid_limit", JSON.parse(response.body).fetch("error")
  end

  private

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end

  def create_profile(brand:, display_name: nil)
    user = User.create!
    membership = BrandMembership.create!(brand:, user:)
    Profile.create!(
      brand:, user:, brand_membership: membership, display_name:,
      birthdate: 30.years.ago.to_date, gender: "person", status: :active, visibility: :visible
    )
  end

  def create_match(first, second)
    profile_a_id, profile_b_id = Match.canonical_pair(first.id, second.id)
    Match.create!(brand: first.brand, profile_a_id:, profile_b_id:)
  end

  def start_conversation(match, user: @viewer.user)
    Messaging::StartConversation.call(user:, brand: match.brand, match_public_id: match.public_id).conversation
  end

  def count_select_queries
    count = 0
    callback = lambda do |_name, _start, _finish, _id, payload|
      count += 1 if payload[:sql].match?(/\ASELECT/i) && payload[:name] != "SCHEMA"
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    count
  end
end
