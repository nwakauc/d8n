require "test_helper"

class Date9jaNotificationMaterializationTest < ActiveSupport::TestCase
  setup do
    @brand = Brand.create!(slug: "date9ja", name: "Date9ja")
    @alice = create_profile(gender: "woman", interested_in: [ "man" ])
    @bob = create_profile(gender: "man", interested_in: [ "woman" ])
    @match = Match.create!(brand: @brand, profile_a_id: [ @alice.id, @bob.id ].min, profile_b_id: [ @alice.id, @bob.id ].max)
    @conversation = Messaging::StartConversation.call(
      user: @alice.user, brand: @brand, match_public_id: @match.public_id
    ).conversation
  end

  test "Date9ja welcome and dating events materialize through shared notifications" do
    like = Like.create!(brand: @brand, liker_profile: @alice, liked_profile: @bob, kind: :like)
    message = Message.create!(brand: @brand, conversation: @conversation, sender_profile: @alice, body: "Hello")
    welcome_event = Notifications::EventPublisher.membership_registered!(membership: @alice.brand_membership)
    like_event = Notifications::EventPublisher.like_received!(like:, recipient: @bob, actor: @alice)
    Notifications::EventPublisher.match_created!(match: @match)
    match_event = NotificationEvent.find_by!(event_type: "match_created", user: @alice.user)
    message_event = Notifications::EventPublisher.message_received!(message:, recipient: @bob)
    events = [ welcome_event, like_event, match_event, message_event ]

    events.each { |event| Notifications::MaterializeEvent.call(event:) }

    assert_equal %w[
      date9ja.welcome date9ja.like_received date9ja.match_created date9ja.message_received
    ].sort, Notification.where(brand: @brand).pluck(:notification_type).sort
  end

  private

  def create_profile(gender:, interested_in:)
    user = User.create!
    membership = BrandMembership.create!(brand: @brand, user:)
    profile = Profile.create!(
      brand: @brand, user:, brand_membership: membership, gender:,
      birthdate: 30.years.ago.to_date, status: :active, visibility: :visible
    )
    ProfilePreference.create!(
      brand: @brand, user:, profile:, min_age: 18, max_age: 60, interested_in:
    )
    profile
  end
end
