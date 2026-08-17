require "test_helper"

class Api::V1::MessagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @brand = Brand.create!(slug: "hookus", name: "HookUs")
    BrandDomain.create!(brand: @brand, host: "hookus.test")
    @ada = create_profile(brand: @brand, display_name: "Ada")
    @sam = create_profile(brand: @brand, display_name: "Sam")
    @match = create_match(@ada, @sam)
    @conversation = start_conversation(@match, user: @ada.user)
    @ada_token, = Session.issue!(brand: @brand, user: @ada.user)
    @sam_token, = Session.issue!(brand: @brand, user: @sam.user)
    host! "hookus.test"
  end

  test "requires authentication for reading and sending" do
    get "/api/v1/conversations/#{@conversation.public_id}/messages"
    assert_response :unauthorized

    post "/api/v1/conversations/#{@conversation.public_id}/messages", params: { body: "hi" }
    assert_response :unauthorized
  end

  test "a matched participant sends a message that persists and both participants retrieve" do
    assert_difference -> { Message.count }, 1 do
      post_message(@ada_token, "Hey Sam")
    end
    assert_response :created
    body = JSON.parse(response.body).fetch("message")
    assert_equal "Hey Sam", body.fetch("body")
    assert_equal @conversation.public_id, body.fetch("conversation_id")
    assert_equal @ada.public_id, body.fetch("sender_id")
    assert body.key?("id")
    assert body.key?("created_at")

    message = Message.sole
    assert_equal @ada.id, message.sender_profile_id
    assert_equal @brand.id, message.brand_id

    # Sender retrieves it.
    get "/api/v1/conversations/#{@conversation.public_id}/messages", headers: bearer_headers(@ada_token)
    assert_response :success
    assert_equal [ "Hey Sam" ], JSON.parse(response.body).fetch("messages").pluck("body")

    # Counterpart retrieves it.
    get "/api/v1/conversations/#{@conversation.public_id}/messages", headers: bearer_headers(@sam_token)
    assert_response :success
    assert_equal [ "Hey Sam" ], JSON.parse(response.body).fetch("messages").pluck("body")
  end

  test "an outsider can neither read nor send in someone else's conversation" do
    outsider = create_profile(brand: @brand)
    outsider_token, = Session.issue!(brand: @brand, user: outsider.user)
    Message.create!(brand: @brand, conversation: @conversation, sender_profile: @ada, body: "private")

    get "/api/v1/conversations/#{@conversation.public_id}/messages", headers: bearer_headers(outsider_token)
    assert_response :not_found
    assert_equal "conversation_unavailable", JSON.parse(response.body).fetch("error")

    assert_no_difference -> { Message.count } do
      post "/api/v1/conversations/#{@conversation.public_id}/messages",
        headers: bearer_headers(outsider_token), params: { body: "let me in" }
    end
    assert_response :not_found
    assert_equal "conversation_unavailable", JSON.parse(response.body).fetch("error")
  end

  test "a conversation from another brand is never reachable" do
    other_brand = Brand.create!(slug: "other", name: "Other")
    other_a = create_profile(brand: other_brand)
    other_b = create_profile(brand: other_brand)
    other_conversation = start_conversation(create_match(other_a, other_b), user: other_a.user)

    get "/api/v1/conversations/#{other_conversation.public_id}/messages", headers: bearer_headers(@ada_token)
    assert_response :not_found
    assert_equal "conversation_unavailable", JSON.parse(response.body).fetch("error")

    post "/api/v1/conversations/#{other_conversation.public_id}/messages",
      headers: bearer_headers(@ada_token), params: { body: "cross brand" }
    assert_response :not_found
  end

  test "an unknown conversation id is unavailable" do
    get "/api/v1/conversations/#{SecureRandom.uuid}/messages", headers: bearer_headers(@ada_token)
    assert_response :not_found
    assert_equal "conversation_unavailable", JSON.parse(response.body).fetch("error")
  end

  test "blocking makes messaging unavailable in both directions" do
    Message.create!(brand: @brand, conversation: @conversation, sender_profile: @ada, body: "earlier")
    Trust::BlockProfile.call(user: @ada.user, brand: @brand, target_public_id: @sam.public_id)

    [ @ada_token, @sam_token ].each do |token|
      get "/api/v1/conversations/#{@conversation.public_id}/messages", headers: bearer_headers(token)
      assert_response :not_found
      assert_equal "conversation_unavailable", JSON.parse(response.body).fetch("error")

      assert_no_difference -> { Message.count } do
        post "/api/v1/conversations/#{@conversation.public_id}/messages",
          headers: bearer_headers(token), params: { body: "still here?" }
      end
      assert_response :not_found
    end
  end

  test "a suspended counterpart makes the conversation unavailable to the other participant" do
    @sam.user.update!(status: :suspended)

    get "/api/v1/conversations/#{@conversation.public_id}/messages", headers: bearer_headers(@ada_token)
    assert_response :not_found
    assert_equal "conversation_unavailable", JSON.parse(response.body).fetch("error")

    assert_no_difference -> { Message.count } do
      post "/api/v1/conversations/#{@conversation.public_id}/messages",
        headers: bearer_headers(@ada_token), params: { body: "hi" }
    end
    assert_response :not_found
  end

  test "empty and whitespace-only messages are rejected" do
    [ "", "   ", "\n\t  " ].each do |body|
      assert_no_difference -> { Message.count } do
        post "/api/v1/conversations/#{@conversation.public_id}/messages",
          headers: bearer_headers(@ada_token), params: { body: }
      end
      assert_response :unprocessable_entity
      assert_equal "message_blank", JSON.parse(response.body).fetch("error")
    end
  end

  test "an oversized message is rejected" do
    assert_no_difference -> { Message.count } do
      post "/api/v1/conversations/#{@conversation.public_id}/messages",
        headers: bearer_headers(@ada_token), params: { body: "a" * (Message::MAX_BODY_LENGTH + 1) }
    end
    assert_response :unprocessable_entity
    assert_equal "message_too_long", JSON.parse(response.body).fetch("error")
  end

  test "a message at the maximum length is accepted" do
    post "/api/v1/conversations/#{@conversation.public_id}/messages",
      headers: bearer_headers(@ada_token), params: { body: "a" * Message::MAX_BODY_LENGTH }
    assert_response :created
  end

  test "unicode and emoji are preserved verbatim" do
    text = "Olá Sam 👋🏽 — café? 日本語 ✅"
    post_message(@ada_token, text)
    assert_response :created
    assert_equal text, JSON.parse(response.body).dig("message", "body")
    assert_equal text, Message.sole.body
  end

  test "messages return newest-first with a deterministic id tiebreak on equal timestamps" do
    same = Time.utc(2026, 8, 17, 12, 0, 0)
    first = Message.create!(brand: @brand, conversation: @conversation, sender_profile: @ada, body: "first")
    second = Message.create!(brand: @brand, conversation: @conversation, sender_profile: @sam, body: "second")
    Message.where(id: [ first.id, second.id ]).update_all(created_at: same)

    get "/api/v1/conversations/#{@conversation.public_id}/messages", headers: bearer_headers(@ada_token)

    assert_response :success
    # Same created_at -> higher id (second) comes first.
    assert_equal [ "second", "first" ], JSON.parse(response.body).fetch("messages").pluck("body")
  end

  test "pagination pages through history without duplicates or gaps" do
    5.times do |index|
      message = Message.create!(brand: @brand, conversation: @conversation, sender_profile: @ada, body: "m#{index}")
      message.update_columns(created_at: Time.utc(2026, 8, 17, 12, 0, index))
    end

    collected = []
    cursor = nil
    pages = 0
    loop do
      query = { limit: 2 }
      query[:cursor] = cursor if cursor
      get "/api/v1/conversations/#{@conversation.public_id}/messages", headers: bearer_headers(@ada_token), params: query
      assert_response :success
      payload = JSON.parse(response.body)
      collected.concat(payload.fetch("messages").pluck("body"))
      cursor = payload.fetch("next_cursor")
      pages += 1
      break if cursor.nil?
      assert_operator pages, :<=, 5, "cursor did not terminate"
    end

    assert_equal %w[m4 m3 m2 m1 m0], collected
    assert_equal collected.uniq, collected
  end

  test "rejects invalid cursors and limits" do
    get "/api/v1/conversations/#{@conversation.public_id}/messages",
      headers: bearer_headers(@ada_token), params: { cursor: "nonsense" }
    assert_response :unprocessable_entity
    assert_equal "invalid_cursor", JSON.parse(response.body).fetch("error")

    get "/api/v1/conversations/#{@conversation.public_id}/messages",
      headers: bearer_headers(@ada_token), params: { limit: 101 }
    assert_response :unprocessable_entity
    assert_equal "invalid_limit", JSON.parse(response.body).fetch("error")
  end

  test "a message cursor cannot be replayed against another conversation" do
    other = create_profile(brand: @brand)
    other_conversation = start_conversation(create_match(@ada, other), user: @ada.user)
    2.times { |i| Message.create!(brand: @brand, conversation: @conversation, sender_profile: @ada, body: "x#{i}") }

    get "/api/v1/conversations/#{@conversation.public_id}/messages",
      headers: bearer_headers(@ada_token), params: { limit: 1 }
    cursor = JSON.parse(response.body).fetch("next_cursor")
    assert cursor.present?

    get "/api/v1/conversations/#{other_conversation.public_id}/messages",
      headers: bearer_headers(@ada_token), params: { cursor: }
    assert_response :unprocessable_entity
    assert_equal "invalid_cursor", JSON.parse(response.body).fetch("error")
  end

  test "the full like-to-message loop works end to end" do
    amy = create_profile(brand: @brand, display_name: "Amy")
    ben = create_profile(brand: @brand, display_name: "Ben")
    amy_token, = Session.issue!(brand: @brand, user: amy.user)
    ben_token, = Session.issue!(brand: @brand, user: ben.user)

    post "/api/v1/profiles/#{ben.public_id}/likes", headers: bearer_headers(amy_token)
    assert_response :created
    post "/api/v1/profiles/#{amy.public_id}/likes", headers: bearer_headers(ben_token)
    assert_response :created
    assert JSON.parse(response.body).fetch("matched")
    match_id = JSON.parse(response.body).fetch("match_id")
    assert match_id.present?

    post "/api/v1/matches/#{match_id}/conversation", headers: bearer_headers(amy_token)
    assert_response :created
    conversation_id = JSON.parse(response.body).dig("conversation", "id")

    post "/api/v1/conversations/#{conversation_id}/messages", headers: bearer_headers(amy_token), params: { body: "Hey" }
    assert_response :created

    # Ben reads "Hey" then replies.
    get "/api/v1/conversations/#{conversation_id}/messages", headers: bearer_headers(ben_token)
    assert_equal [ "Hey" ], JSON.parse(response.body).fetch("messages").pluck("body")
    post "/api/v1/conversations/#{conversation_id}/messages", headers: bearer_headers(ben_token), params: { body: "Hi Amy" }
    assert_response :created

    # Amy sees both, newest first.
    get "/api/v1/conversations/#{conversation_id}/messages", headers: bearer_headers(amy_token)
    assert_equal [ "Hi Amy", "Hey" ], JSON.parse(response.body).fetch("messages").pluck("body")
  end

  test "the conversation list surfaces the latest message preview" do
    Message.create!(brand: @brand, conversation: @conversation, sender_profile: @ada, body: "first")
    latest = Message.create!(brand: @brand, conversation: @conversation, sender_profile: @sam, body: "latest")
    latest.update_columns(created_at: 1.minute.from_now)

    get "/api/v1/conversations", headers: bearer_headers(@ada_token)

    assert_response :success
    card = JSON.parse(response.body).fetch("conversations").sole
    assert_equal "latest", card.dig("last_message", "body")
    assert_equal @sam.public_id, card.dig("last_message", "sender_id")
    assert card.dig("last_message", "created_at").present?
  end

  test "an empty conversation lists a null last message" do
    get "/api/v1/conversations", headers: bearer_headers(@ada_token)

    assert_response :success
    assert_nil JSON.parse(response.body).fetch("conversations").sole.fetch("last_message")
  end

  private

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end

  def post_message(token, body)
    post "/api/v1/conversations/#{@conversation.public_id}/messages",
      headers: bearer_headers(token), params: { body: }
  end

  def create_profile(brand:, display_name: nil)
    user = User.create!
    membership = BrandMembership.create!(brand:, user:)
    profile = Profile.create!(
      brand:, user:, brand_membership: membership, display_name:,
      birthdate: 30.years.ago.to_date, gender: "person", status: :active, visibility: :visible
    )
    ProfilePreference.create!(
      brand:, user:, profile:, min_age: 18, max_age: 80, interested_in: [ "person" ]
    )
    profile
  end

  def create_match(first, second)
    profile_a_id, profile_b_id = Match.canonical_pair(first.id, second.id)
    Match.create!(brand: first.brand, profile_a_id:, profile_b_id:)
  end

  def start_conversation(match, user:)
    Messaging::StartConversation.call(user:, brand: match.brand, match_public_id: match.public_id).conversation
  end
end
