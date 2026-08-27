require "test_helper"

# T4: covers the five D8N dating notification events (like_received,
# match_created, opener_received, message_received — opener_replied is
# deliberately never materialized, see domains/hooks/reply_to_hook.rb) end to
# end through the real domain services and the existing notification
# infrastructure (NotificationEvent -> ProcessEventJob -> MaterializeEvent ->
# Notification/NotificationDelivery -> Api::V1::NotificationsController).
class DatingNotificationsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @brand = Brand.create!(slug: "dateza", name: "DateZA")
    Profiles::DatezaProfileCatalog.install!(brand: @brand)
    BrandDomain.create!(brand: @brand, host: "dateza.test")
    host! "dateza.test"
  end

  # -- like_received ----------------------------------------------------------

  test "a non-mutual like publishes exactly one like_received notification to the recipient, not the sender" do
    liker = create_member(gender: "woman", interested_in: %w[man])
    target = create_member(gender: "man", interested_in: %w[woman])

    assert_difference -> { Notification.count }, 1 do
      perform_enqueued_jobs(only: Notifications::ProcessEventJob) do
        Matching::LikeProfile.call(user: liker.user, brand: @brand, target_public_id: target.public_id)
      end
    end

    notification = Notification.find_by!(brand_membership: target.brand_membership)
    assert_equal "dateza.like_received", notification.notification_type
    assert_equal liker.public_id, notification.payload.fetch("actor").fetch("profile_id")
    assert_equal "profile", notification.payload.fetch("target").fetch("type")
    assert_equal liker.public_id, notification.payload.fetch("target").fetch("id")
    assert_equal 0, Notification.where(brand_membership: liker.brand_membership).count
    assert_equal 1, notification.notification_deliveries.in_app.sent.count
  end

  test "an idempotent replay of an existing like does not duplicate the notification event" do
    liker = create_member(gender: "woman", interested_in: %w[man])
    target = create_member(gender: "man", interested_in: %w[woman])
    Matching::LikeProfile.call(user: liker.user, brand: @brand, target_public_id: target.public_id)

    assert_no_difference -> { NotificationEvent.count } do
      Matching::LikeProfile.call(user: liker.user, brand: @brand, target_public_id: target.public_id)
    end
  end

  test "a reciprocal like that creates a match publishes match_created instead of like_received" do
    alice = create_member(gender: "woman", interested_in: %w[man])
    bob = create_member(gender: "man", interested_in: %w[woman])
    Matching::LikeProfile.call(user: alice.user, brand: @brand, target_public_id: bob.public_id)

    assert_difference -> { Notification.count }, 2 do
      perform_enqueued_jobs(only: Notifications::ProcessEventJob) do
        Matching::LikeProfile.call(user: bob.user, brand: @brand, target_public_id: alice.public_id)
      end
    end

    assert_equal 0, NotificationEvent.where(event_type: "like_received", brand_membership: alice.brand_membership).count
    match = Match.last
    [ alice, bob ].each do |profile|
      notification = Notification.joins(:notification_event).find_by!(
        brand_membership: profile.brand_membership, notification_event: { event_type: "match_created" }
      )
      assert_equal "dateza.match_created", notification.notification_type
      assert_equal "match", notification.payload.fetch("target").fetch("type")
      assert_equal match.public_id, notification.payload.fetch("target").fetch("id")
    end
    alice_notification = Notification.joins(:notification_event)
      .find_by!(brand_membership: alice.brand_membership, notification_event: { event_type: "match_created" })
    assert_equal bob.public_id, alice_notification.payload.fetch("actor").fetch("profile_id")
  end

  test "a blocked or ineligible target never produces a like_received event" do
    liker = create_member(gender: "woman", interested_in: %w[man])
    target = create_member(gender: "man", interested_in: %w[woman])
    Trust::BlockProfile.call(user: target.user, brand: @brand, target_public_id: liker.public_id)

    assert_no_difference -> { NotificationEvent.count } do
      assert_raises(Matching::InteractionError) do
        Matching::LikeProfile.call(user: liker.user, brand: @brand, target_public_id: target.public_id)
      end
    end
  end

  test "calling match_created! twice for the same match does not duplicate notification events" do
    alice = create_member(gender: "woman", interested_in: %w[man])
    bob = create_member(gender: "man", interested_in: %w[woman])
    profile_a_id, profile_b_id = Match.canonical_pair(alice.id, bob.id)
    match = Match.create!(brand: @brand, profile_a_id:, profile_b_id:)

    Notifications::EventPublisher.match_created!(match:)
    assert_no_difference -> { NotificationEvent.count } do
      Notifications::EventPublisher.match_created!(match:)
    end
  end

  # -- opener_received ----------------------------------------------------------

  test "a successful opener send publishes exactly one opener_received notification to the recipient" do
    sender = create_member(gender: "woman", interested_in: %w[man])
    recipient = create_member(gender: "man", interested_in: %w[woman])

    assert_difference -> { Notification.count }, 1 do
      perform_enqueued_jobs(only: Notifications::ProcessEventJob) do
        Hooks::SendHook.call(user: sender.user, brand: @brand, target_public_id: recipient.public_id, opener_key: "coffee_or_tea")
      end
    end

    hook = Hook.find_by!(brand: @brand, sender_profile: sender, recipient_profile: recipient)
    notification = Notification.find_by!(brand_membership: recipient.brand_membership)
    assert_equal "dateza.opener_received", notification.notification_type
    assert_equal sender.public_id, notification.payload.fetch("actor").fetch("profile_id")
    assert_equal "opener", notification.payload.fetch("target").fetch("type")
    assert_equal hook.public_id, notification.payload.fetch("target").fetch("id")
    assert_equal 0, Notification.where(brand_membership: sender.brand_membership).count
  end

  test "a rejected opener send (invalid catalog key) publishes nothing" do
    sender = create_member(gender: "woman", interested_in: %w[man])
    recipient = create_member(gender: "man", interested_in: %w[woman])

    assert_no_difference -> { NotificationEvent.count } do
      assert_raises(Matching::InteractionError) do
        Hooks::SendHook.call(user: sender.user, brand: @brand, target_public_id: recipient.public_id, opener_key: "not_a_real_key")
      end
    end
  end

  test "a rate-limited opener send publishes nothing" do
    sender = create_member(gender: "woman", interested_in: %w[man])
    Hooks::Policy::FREE_DAILY_LIMIT.times do
      target = create_member(gender: "man", interested_in: %w[woman])
      Hooks::SendHook.call(user: sender.user, brand: @brand, target_public_id: target.public_id, opener_key: "coffee_or_tea")
    end
    one_more = create_member(gender: "man", interested_in: %w[woman])

    assert_no_difference -> { NotificationEvent.where(event_type: "opener_received").count } do
      assert_raises(Matching::InteractionError) do
        Hooks::SendHook.call(user: sender.user, brand: @brand, target_public_id: one_more.public_id, opener_key: "coffee_or_tea")
      end
    end
  end

  test "replaying opener_received materialization for the same Hook does not duplicate" do
    sender = create_member(gender: "woman", interested_in: %w[man])
    recipient = create_member(gender: "man", interested_in: %w[woman])
    Hooks::SendHook.call(user: sender.user, brand: @brand, target_public_id: recipient.public_id, opener_key: "coffee_or_tea")
    hook = Hook.find_by!(brand: @brand, sender_profile: sender, recipient_profile: recipient)

    assert_no_difference -> { NotificationEvent.count } do
      Notifications::EventPublisher.opener_received!(hook:)
    end
  end

  # -- opener reply: match_created only, never a separate opener_replied ------

  test "a successful opener reply publishes match_created to both participants and no opener_replied type exists" do
    sender = create_member(gender: "woman", interested_in: %w[man])
    recipient = create_member(gender: "man", interested_in: %w[woman])
    Hooks::SendHook.call(user: sender.user, brand: @brand, target_public_id: recipient.public_id, opener_key: "coffee_or_tea")
    hook = Hook.find_by!(brand: @brand, sender_profile: sender, recipient_profile: recipient)
    perform_enqueued_jobs(only: Notifications::ProcessEventJob) # drain the opener_received job first

    assert_difference -> { Notification.count }, 2 do
      perform_enqueued_jobs(only: Notifications::ProcessEventJob) do
        Hooks::ReplyToHook.call(user: recipient.user, brand: @brand, hook_public_id: hook.public_id, message: "Sure!")
      end
    end

    assert_equal 0, NotificationEvent.where(event_type: "opener_replied").count
    match = Match.last
    [ sender, recipient ].each do |profile|
      notification = Notification.joins(:notification_event).find_by!(
        brand_membership: profile.brand_membership, notification_event: { event_type: "match_created" }
      )
      assert_equal match.public_id, notification.payload.fetch("target").fetch("id")
    end
  end

  test "replaying opener-reply match materialization does not duplicate the sender's notification" do
    sender = create_member(gender: "woman", interested_in: %w[man])
    recipient = create_member(gender: "man", interested_in: %w[woman])
    Hooks::SendHook.call(user: sender.user, brand: @brand, target_public_id: recipient.public_id, opener_key: "coffee_or_tea")
    hook = Hook.find_by!(brand: @brand, sender_profile: sender, recipient_profile: recipient)
    Hooks::ReplyToHook.call(user: recipient.user, brand: @brand, hook_public_id: hook.public_id, message: "Sure!")
    match = Match.last

    assert_no_difference -> { NotificationEvent.count } do
      Notifications::EventPublisher.match_created!(match:)
    end
  end

  # -- message_received ----------------------------------------------------------

  test "a successful message publishes exactly one message_received notification to the other participant" do
    alice = create_member(gender: "woman", interested_in: %w[man])
    bob = create_member(gender: "man", interested_in: %w[woman])
    match = create_active_match(alice, bob)
    conversation = Messaging::StartConversation.call(user: alice.user, brand: @brand, match_public_id: match.public_id).conversation

    assert_difference -> { Notification.count }, 1 do
      perform_enqueued_jobs(only: Notifications::ProcessEventJob) do
        Messaging::SendMessage.call(user: alice.user, brand: @brand, conversation_public_id: conversation.public_id, body: "Hi!")
      end
    end

    notification = Notification.find_by!(brand_membership: bob.brand_membership)
    assert_equal "dateza.message_received", notification.notification_type
    assert_equal alice.public_id, notification.payload.fetch("actor").fetch("profile_id")
    assert_equal "conversation", notification.payload.fetch("target").fetch("type")
    assert_equal conversation.public_id, notification.payload.fetch("target").fetch("id")
    assert_equal 0, Notification.where(brand_membership: alice.brand_membership).count
  end

  test "a blocked relationship raises before any message_received event can be created" do
    alice = create_member(gender: "woman", interested_in: %w[man])
    bob = create_member(gender: "man", interested_in: %w[woman])
    match = create_active_match(alice, bob)
    conversation = Messaging::StartConversation.call(user: alice.user, brand: @brand, match_public_id: match.public_id).conversation
    Trust::BlockProfile.call(user: alice.user, brand: @brand, target_public_id: bob.public_id)

    assert_no_difference -> { NotificationEvent.count } do
      assert_raises(Messaging::AccessError) do
        Messaging::SendMessage.call(user: alice.user, brand: @brand, conversation_public_id: conversation.public_id, body: "hi")
      end
    end
  end

  test "an unavailable/ended conversation raises before any message_received event can be created" do
    alice = create_member(gender: "woman", interested_in: %w[man])
    bob = create_member(gender: "man", interested_in: %w[woman])
    match = create_active_match(alice, bob)
    conversation = Messaging::StartConversation.call(user: alice.user, brand: @brand, match_public_id: match.public_id).conversation
    match.update!(status: :ended)

    assert_no_difference -> { NotificationEvent.count } do
      assert_raises(Messaging::AccessError) do
        Messaging::SendMessage.call(user: alice.user, brand: @brand, conversation_public_id: conversation.public_id, body: "hi")
      end
    end
  end

  test "replaying message_received materialization for the same Message does not duplicate" do
    alice = create_member(gender: "woman", interested_in: %w[man])
    bob = create_member(gender: "man", interested_in: %w[woman])
    match = create_active_match(alice, bob)
    conversation = Messaging::StartConversation.call(user: alice.user, brand: @brand, match_public_id: match.public_id).conversation
    result = Messaging::SendMessage.call(user: alice.user, brand: @brand, conversation_public_id: conversation.public_id, body: "Hi!")

    assert_no_difference -> { NotificationEvent.count } do
      Notifications::EventPublisher.message_received!(message: result.message, recipient: bob)
    end
  end

  # -- payload / inbox integration ------------------------------------------

  test "the notifications inbox exposes only opaque public identifiers for a dating event, nothing more" do
    liker = create_member(gender: "woman", interested_in: %w[man])
    target = create_member(gender: "man", interested_in: %w[woman])
    perform_enqueued_jobs(only: Notifications::ProcessEventJob) do
      Matching::LikeProfile.call(user: liker.user, brand: @brand, target_public_id: target.public_id)
    end
    token, = Session.issue!(brand: @brand, user: target.user, credential: verified_credential(target))

    get "/api/v1/notifications", headers: auth(token)

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 1, body.fetch("unread_count")
    notification = body.fetch("notifications").sole
    assert_equal "dateza.like_received", notification.fetch("type")
    payload = notification.fetch("payload")
    assert_equal %w[actor target], payload.keys.sort
    assert_equal %w[profile_id], payload.fetch("actor").keys
    assert_equal %w[id type], payload.fetch("target").keys.sort
    assert_equal liker.public_id, payload.dig("actor", "profile_id")
    assert_not_includes response.body, "recipient"
    assert_not_includes response.body, "provider"
    assert_not_includes response.body, "external_id"
  end

  test "a dating notification fully participates in the existing inbox: unread count, mark-read, mark-all-read" do
    liker = create_member(gender: "woman", interested_in: %w[man])
    target = create_member(gender: "man", interested_in: %w[woman])
    perform_enqueued_jobs(only: Notifications::ProcessEventJob) do
      Matching::LikeProfile.call(user: liker.user, brand: @brand, target_public_id: target.public_id)
    end
    token, = Session.issue!(brand: @brand, user: target.user, credential: verified_credential(target))

    get "/api/v1/notifications", headers: auth(token)
    body = JSON.parse(response.body)
    assert_equal 1, body.fetch("unread_count")
    notification_id = body.fetch("notifications").sole.fetch("id")

    patch "/api/v1/notifications/#{notification_id}/read", headers: auth(token)
    assert_response :success
    assert JSON.parse(response.body).dig("notification", "read_at").present?

    get "/api/v1/notifications", headers: auth(token)
    assert_equal 0, JSON.parse(response.body).fetch("unread_count")

    another_target = create_member(gender: "man", interested_in: %w[woman])
    perform_enqueued_jobs(only: Notifications::ProcessEventJob) do
      Matching::LikeProfile.call(user: liker.user, brand: @brand, target_public_id: another_target.public_id)
    end
    another_token, = Session.issue!(brand: @brand, user: another_target.user, credential: verified_credential(another_target))
    post "/api/v1/notifications/read_all", headers: auth(another_token)
    assert_response :success
    assert_equal 1, JSON.parse(response.body).fetch("marked_read")
    assert_equal 0, JSON.parse(response.body).fetch("unread_count")
  end

  # -- actor lifecycle / block safety -----------------------------------------

  test "a notification whose actor is later blocked stores only an opaque id and cannot be used to bypass the block" do
    liker = create_member(gender: "woman", interested_in: %w[man])
    target = create_member(gender: "man", interested_in: %w[woman])
    perform_enqueued_jobs(only: Notifications::ProcessEventJob) do
      Matching::LikeProfile.call(user: liker.user, brand: @brand, target_public_id: target.public_id)
    end
    Trust::BlockProfile.call(user: target.user, brand: @brand, target_public_id: liker.public_id)
    token, = Session.issue!(brand: @brand, user: target.user, credential: verified_credential(target))

    get "/api/v1/notifications", headers: auth(token)
    assert_response :success
    notification = JSON.parse(response.body).fetch("notifications").sole
    # Only the opaque id survives — no name/photo/bio was ever embedded, so
    # there is nothing about the now-blocked actor left to leak.
    assert_equal liker.public_id, notification.dig("payload", "actor", "profile_id")

    # Attempting to act on that id through the normal profile-detail endpoint
    # fails closed via Trust's existing block enforcement — no bypass.
    get "/api/v1/profiles/#{liker.public_id}", headers: auth(token)
    assert_response :not_found
  end

  # -- brand isolation ----------------------------------------------------------

  test "HookUs materializes no dating notification events today (no notify.event/notify.inbox plan)" do
    hookus = Brand.create!(slug: "hookus", name: "HookUs")
    BrandDomain.create!(brand: hookus, host: "hookus.test")
    liker = create_hookus_member(hookus, gender: "woman", interested_in: %w[man])
    target = create_hookus_member(hookus, gender: "man", interested_in: %w[woman])

    assert_no_difference -> { NotificationEvent.count } do
      Matching::LikeProfile.call(user: liker.user, brand: hookus, target_public_id: target.public_id)
    end
  end

  test "the same identity's DateZA like_received notification never leaks into their HookUs inbox" do
    hookus = Brand.create!(slug: "hookus", name: "HookUs")
    BrandDomain.create!(brand: hookus, host: "hookus.test")
    liker = create_member(gender: "woman", interested_in: %w[man])
    target = create_member(gender: "man", interested_in: %w[woman])
    BrandMembership.create!(brand: hookus, user: target.user, status: :active)
    perform_enqueued_jobs(only: Notifications::ProcessEventJob) do
      Matching::LikeProfile.call(user: liker.user, brand: @brand, target_public_id: target.public_id)
    end

    assert_equal 1, Notifications::Inbox.scope(brand: @brand, user: target.user).count
    assert_equal 0, Notifications::Inbox.scope(brand: hookus, user: target.user).count
  end

  # -- T5 delivery-preference integration --------------------------------------
  # Focused evidence that T5's preferences actually gate T4 delivery, without
  # re-testing the full T4 event suite.

  test "with product_email_enabled (the default), a dating event still creates an email delivery" do
    liker = create_member(gender: "woman", interested_in: %w[man])
    target = create_member(gender: "man", interested_in: %w[woman])

    perform_enqueued_jobs(only: Notifications::ProcessEventJob) do
      Matching::LikeProfile.call(user: liker.user, brand: @brand, target_public_id: target.public_id)
    end

    notification = Notification.find_by!(brand_membership: target.brand_membership)
    assert_equal 1, notification.notification_deliveries.in_app.sent.count
    assert_equal 1, notification.notification_deliveries.email.count
  end

  test "disabling product_email_enabled still materializes the in-app notification but suppresses the email delivery" do
    liker = create_member(gender: "woman", interested_in: %w[man])
    target = create_member(gender: "man", interested_in: %w[woman])
    NotificationPreference.create!(
      brand: @brand, user: target.user, brand_membership: target.brand_membership, product_email_enabled: false
    )

    perform_enqueued_jobs(only: Notifications::ProcessEventJob) do
      Matching::LikeProfile.call(user: liker.user, brand: @brand, target_public_id: target.public_id)
    end

    notification = Notification.find_by!(brand_membership: target.brand_membership)
    assert_equal "dateza.like_received", notification.notification_type
    assert_equal 1, notification.notification_deliveries.in_app.sent.count
    assert_equal 0, notification.notification_deliveries.email.count
    # The in-app notification is fully intact and visible in the inbox regardless of the email preference.
    assert_equal 1, Notifications::Inbox.scope(brand: @brand, user: target.user).unread.count
  end

  test "re-enabling product_email_enabled allows a future dating event to email again" do
    liker = create_member(gender: "woman", interested_in: %w[man])
    target = create_member(gender: "man", interested_in: %w[woman])
    preference = NotificationPreference.create!(
      brand: @brand, user: target.user, brand_membership: target.brand_membership, product_email_enabled: false
    )
    perform_enqueued_jobs(only: Notifications::ProcessEventJob) do
      Matching::LikeProfile.call(user: liker.user, brand: @brand, target_public_id: target.public_id)
    end
    assert_equal 0, Notification.find_by!(brand_membership: target.brand_membership).notification_deliveries.email.count

    preference.update!(product_email_enabled: true)
    another_liker = create_member(gender: "woman", interested_in: %w[man])
    perform_enqueued_jobs(only: Notifications::ProcessEventJob) do
      Matching::LikeProfile.call(user: another_liker.user, brand: @brand, target_public_id: target.public_id)
    end

    new_notification = Notification.joins(:notification_event).where(
      brand_membership: target.brand_membership, notification_event: { event_type: "like_received" }
    ).order(:id).last
    assert_equal 1, new_notification.notification_deliveries.email.count
  end

  test "push_enabled is respected at the existing delivery boundary Notifications::Policy already gates" do
    target = create_member(gender: "man", interested_in: %w[woman])
    membership = target.brand_membership

    assert Notifications::Policy.channel_allowed?(membership:, category: :push)

    NotificationPreference.create!(brand: @brand, user: target.user, brand_membership: membership, push_enabled: false)

    assert_not Notifications::Policy.channel_allowed?(membership:, category: :push)
  end

  private

  def auth(token)
    { "Authorization" => "Bearer #{token}" }
  end

  def create_member(gender:, interested_in:)
    user = User.create!
    membership = BrandMembership.create!(brand: @brand, user:, status: :active)
    profile = Profile.create!(
      brand: @brand, user:, brand_membership: membership, display_name: "Member",
      gender:, birthdate: 28.years.ago.to_date, status: :active, visibility: :visible
    )
    ProfilePreference.create!(brand: @brand, user:, profile:, min_age: 18, max_age: 60, interested_in:)
    IdentityIdentifier.create!(user:, kind: :email, normalized_value: "#{SecureRandom.hex(6)}@example.com", verified_at: Time.current)
    profile
  end

  def create_hookus_member(brand, gender:, interested_in:)
    user = User.create!
    membership = BrandMembership.create!(brand:, user:, status: :active)
    profile = Profile.create!(
      brand:, user:, brand_membership: membership, gender:,
      birthdate: 28.years.ago.to_date, status: :active, visibility: :visible
    )
    ProfilePreference.create!(brand:, user:, profile:, min_age: 18, max_age: 60, interested_in:)
    profile
  end

  def verified_credential(profile)
    identifier = IdentityIdentifier.kept.contact.find_by!(user: profile.user)
    Credential.create!(user: profile.user, identity_identifier: identifier, kind: :password)
  end

  def create_active_match(first, second)
    profile_a_id, profile_b_id = Match.canonical_pair(first.id, second.id)
    Match.create!(brand: @brand, profile_a_id:, profile_b_id:)
  end
end
