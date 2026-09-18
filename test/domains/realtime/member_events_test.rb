require "test_helper"

class Realtime::MemberEventsTest < ActiveSupport::TestCase
  test "channels separate both brand and user and contain no client-selected IDs" do
    assert_not_equal Realtime::MemberEvents.stream_name(brand_id: 1, user_id: 7), Realtime::MemberEvents.stream_name(brand_id: 2, user_id: 7)
    assert_not_equal Realtime::MemberEvents.stream_name(brand_id: 1, user_id: 7), Realtime::MemberEvents.stream_name(brand_id: 1, user_id: 8)
  end

  test "session validity rechecks revocation expiry suspended user and membership" do
    brand = Brand.create!(slug: "hookus", name: "HookUs")
    user = User.create!
    membership = BrandMembership.create!(brand:, user:)
    _, session = Session.issue!(brand:, user:)
    ids = { session_id: session.id, brand_id: brand.id, user_id: user.id }
    assert Realtime::MemberEvents.session_active?(**ids)
    membership.update!(status: :suspended)
    assert_not Realtime::MemberEvents.session_active?(**ids)
    membership.update!(status: :active)
    user.update!(status: :suspended)
    assert_not Realtime::MemberEvents.session_active?(**ids)
    user.update!(status: :active)
    session.update!(revoked_at: Time.current)
    assert_not Realtime::MemberEvents.session_active?(**ids)
    session.update!(revoked_at: nil, expires_at: 1.minute.ago)
    assert_not Realtime::MemberEvents.session_active?(**ids)
    assert_not Realtime::MemberEvents.session_active?(**ids.merge(brand_id: brand.id + 1))
  end
  test "message hints route to each current-brand participant, distinguish own events and omit content" do
    brand = Brand.create!(slug: "hookus", name: "HookUs")
    profiles = 2.times.map do
      user = User.create!
      membership = BrandMembership.create!(brand:, user:)
      Profile.create!(brand:, user:, brand_membership: membership, birthdate: 30.years.ago.to_date,
        gender: "person", status: :active, visibility: :visible)
    end
    a, b = profiles
    match = Match.create!(brand:, profile_a: a, profile_b: b)
    conversation = Messaging::StartConversation.call(user: a.user, brand:, match_public_id: match.public_id).conversation
    message = Message.create!(brand:, conversation:, sender_profile: a, body: "private content")
    captured = []
    stub_method(ActionCable.server, :broadcast, ->(channel, data) { captured << [ channel, data ] }) do
      Realtime::MemberEvents.message_created(message)
    end
    assert_equal 2, captured.size
    assert_equal [ false, true ], captured.map { |_, data| data[:incoming] }
    assert_equal [ a.user_id, b.user_id ].map { |id| Realtime::MemberEvents.stream_name(brand_id: brand.id, user_id: id) }, captured.map(&:first)
    assert captured.all? { |_, data| data[:message_id] == message.public_id }
    assert_not_includes captured.to_json, "private content"
  end
end
