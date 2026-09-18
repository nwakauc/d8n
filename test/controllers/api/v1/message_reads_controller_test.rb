require "test_helper"

class Api::V1::MessageReadsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @brand = Brand.create!(slug: "hookus", name: "HookUs")
    BrandDomain.create!(brand: @brand, host: "hookus.test")
    @viewer = create_profile(brand: @brand)
    @other = create_profile(brand: @brand)
    @conversation = conversation(@viewer, @other)
    @token, = Session.issue!(user: @viewer.user, brand: @brand)
    host! "hookus.test"
  end

  test "counts incoming messages globally and per conversation, excluding own messages" do
    3.times { create_message(@conversation, @other) }
    create_message(@conversation, @viewer)
    another = create_profile(brand: @brand)
    second = conversation(@viewer, another)
    2.times { create_message(second, another) }
    get "/api/v1/messages/unread", headers: headers
    assert_response :success
    assert_equal 5, json.fetch("unread_message_count")
    assert_equal({ @conversation.public_id => 3, second.public_id => 2 }, json.fetch("conversations"))
    get "/api/v1/conversations", headers: headers
    assert_equal [ 2, 3 ], json.fetch("conversations").pluck("unread_message_count").sort
  end

  test "reads only displayed incoming IDs idempotently, persists across refresh and keeps concurrent unread messages" do
    shown = create_message(@conversation, @other)
    unseen = create_message(@conversation, @other)
    2.times do
      post "/api/v1/conversations/#{@conversation.public_id}/read", headers: headers, params: { message_ids: [ shown.public_id ] }
      assert_response :success
      assert_equal 1, json.fetch("unread_message_count")
    end
    assert_equal 1, MessageRead.count
    get "/api/v1/messages/unread", headers: headers
    assert_equal 1, json.fetch("unread_message_count")
    post "/api/v1/conversations/#{@conversation.public_id}/read", headers: headers, params: { message_ids: [ unseen.public_id ] }
    assert_equal 0, json.fetch("unread_message_count")
  end

  test "rejects unauthenticated, outsider, unknown and cross-brand IDs without disclosing conversation data" do
    get "/api/v1/messages/unread"
    assert_response :unauthorized
    outsider = create_profile(brand: @brand)
    token, = Session.issue!(user: outsider.user, brand: @brand)
    post "/api/v1/conversations/#{@conversation.public_id}/read", headers: { "Authorization" => "Bearer #{token}" }, params: { message_ids: [ SecureRandom.uuid ] }
    assert_response :not_found
    post "/api/v1/conversations/#{SecureRandom.uuid}/read", headers: headers, params: { message_ids: [ SecureRandom.uuid ] }
    assert_response :not_found
    other_brand = Brand.create!(slug: "other", name: "Other")
    foreign = conversation(create_profile(brand: other_brand), create_profile(brand: other_brand))
    post "/api/v1/conversations/#{foreign.public_id}/read", headers: headers, params: { message_ids: [ SecureRandom.uuid ] }
    assert_response :not_found
  end

  test "cannot acknowledge a message from a different conversation; deleted and blocked messages do not count" do
    incoming = create_message(@conversation, @other)
    incoming.update!(deleted_at: Time.current)
    get "/api/v1/messages/unread", headers: headers
    assert_equal 0, json.fetch("unread_message_count")
    incoming.update!(deleted_at: nil)
    post "/api/v1/conversations/#{@conversation.public_id}/read", headers: headers, params: { message_ids: [ SecureRandom.uuid ] }
    assert_response :unprocessable_entity
    Trust::BlockProfile.call(user: @viewer.user, brand: @brand, target_public_id: @other.public_id)
    get "/api/v1/messages/unread", headers: headers
    assert_equal 0, json.fetch("unread_message_count")
    post "/api/v1/conversations/#{@conversation.public_id}/read", headers: headers, params: { message_ids: [ incoming.public_id ] }
    assert_response :not_found
  end

  test "reading a displayed message also reads matching notifications, including delayed outbox materialization" do
    @brand.update!(slug: "date9ja")
    incoming = create_message(@conversation, @other)
    event = Notifications::EventPublisher.message_received!(message: incoming, recipient: @viewer)
    post "/api/v1/conversations/#{@conversation.public_id}/read", headers: headers, params: { message_ids: [ incoming.public_id ] }
    notification = Notifications::MaterializeEvent.call(event:)
    assert notification.reload.read_at
    assert_equal 0, Notifications::Inbox.scope(brand: @brand, user: @viewer.user).unread.count
  end

  private

  def headers
    { "Authorization" => "Bearer #{@token}" }
  end

  def json
    JSON.parse(response.body)
  end

  def create_profile(brand:)
    user = User.create!
    membership = BrandMembership.create!(user:, brand:)
    Profile.create!(user:, brand:, brand_membership: membership, status: :active, visibility: :visible,
      birthdate: 30.years.ago.to_date, gender: :woman, country_code: "NG", display_name: "Ada")
  end

  def conversation(a, b)
    profile_a_id, profile_b_id = Match.canonical_pair(a.id, b.id)
    match = Match.create!(brand: a.brand, profile_a_id:, profile_b_id:, status: :active)
    Messaging::StartConversation.call(user: a.user, brand: a.brand, match_public_id: match.public_id).conversation
  end

  def create_message(conversation, sender)
    Message.create!(brand: sender.brand, conversation:, sender_profile: sender, body: "hello")
  end
end
