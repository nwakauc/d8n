require "test_helper"

class DatezaProductNotificationMailerTest < ActionMailer::TestCase
  setup do
    @brand = Brand.create!(slug: "dateza", name: "DateZA")
    Profiles::DatezaProfileCatalog.install!(brand: @brand)
    @sender = create_member("Inga")
    @recipient = create_member("Thabo")
    profile_a_id, profile_b_id = Match.canonical_pair(@sender.id, @recipient.id)
    @match = Match.create!(brand: @brand, profile_a_id:, profile_b_id:)
    @conversation = Messaging::StartConversation.call(
      user: @sender.user, brand: @brand, match_public_id: @match.public_id
    ).conversation
    ActiveStorage::Current.url_options = { host: "dateza.test", protocol: "https" }
  end

  teardown do
    ActiveStorage::Current.url_options = nil
  end

  test "message email includes sender identity, current safe profile image, truncated preview, and conversation CTA" do
    attach_safe_profile_photo(@sender)
    body = "  This is a useful private message   with irregular spacing " + ("and more words " * 12)
    notification = message_notification(body:)

    mail = render_notification(notification)
    html = mail.html_part.body.decoded
    text = mail.text_part.body.decoded

    assert_equal "Inga sent you a message on DateZA", mail.subject
    assert_includes html, "A message from Inga"
    assert_includes html, "alt=\"Inga\""
    assert_includes html, "display.jpg"
    assert_includes html, "https://www.date-za.com/conversations/#{@conversation.public_id}"
    assert_includes text, "Reply to Inga"
    preview = Notifications::EmailPresenters::Dateza.call(notification:).preview
    assert_operator preview.length, :<=, 100
    assert_equal preview, preview.squish
    assert_includes html, ERB::Util.html_escape(preview)
  end

  test "unsafe sender and message content is escaped in HTML" do
    @sender.update!(display_name: "<script>alert(1)</script>")
    notification = message_notification(body: "Hello <img src=x onerror=alert(2)> & goodbye")

    html = render_notification(notification).html_part.body.decoded

    assert_not_includes html, "<script>alert(1)</script>"
    assert_not_includes html, "<img src=x onerror=alert(2)>"
    assert_includes html, "&lt;script&gt;alert(1)&lt;/script&gt;"
    assert_includes html, "&lt;img src=x onerror=alert(2)&gt;"
  end

  test "media-only messages use semantic copy and never embed private message media" do
    message = Message.new(brand: @brand, conversation: @conversation, sender_profile: @sender, body: nil)
    message.message_attachments.build(brand: @brand, media_kind: :image, position: 0, processing_state: :pending)
    message.save!
    notification = publish_and_materialize(message)

    mail = render_notification(notification)

    assert_includes mail.html_part.body.decoded, "Inga sent you a photo."
    assert_includes mail.text_part.body.decoded, "Private message media is never attached"
    assert_nil Notifications::EmailPresenters::Dateza.call(notification:).preview
    assert_not_includes mail.to_s, "message_attachments"
  end

  test "blocked or deleted message contexts expose no sender identity or preview" do
    secret = "private words that must disappear"
    blocked_notification = message_notification(body: secret)
    Trust::BlockProfile.call(user: @recipient.user, brand: @brand, target_public_id: @sender.public_id)

    blocked_mail = render_notification(blocked_notification)
    assert_equal "New message on DateZA", blocked_mail.subject
    assert_not_includes blocked_mail.to_s, "Inga"
    assert_not_includes blocked_mail.to_s, secret
    assert_not_includes blocked_mail.to_s, @conversation.public_id

    # Recreate an eligible relationship to prove message deletion is checked
    # independently of block/match state.
    other_sender = create_member("Lerato")
    profile_a_id, profile_b_id = Match.canonical_pair(other_sender.id, @recipient.id)
    match = Match.create!(brand: @brand, profile_a_id:, profile_b_id:)
    conversation = Messaging::StartConversation.call(
      user: other_sender.user, brand: @brand, match_public_id: match.public_id
    ).conversation
    message = Message.create!(brand: @brand, conversation:, sender_profile: other_sender, body: secret)
    deleted_notification = publish_and_materialize(message, recipient: @recipient)
    message.update!(deleted_at: Time.current)

    deleted_mail = render_notification(deleted_notification)
    assert_not_includes deleted_mail.to_s, "Lerato"
    assert_not_includes deleted_mail.to_s, secret
  end

  test "match email carries relevant brand copy, counterpart identity, image-safe CTA path" do
    Notifications::EventPublisher.match_created!(match: @match)
    event = NotificationEvent.find_by!(event_type: "match_created", user: @recipient.user)
    Notifications::ProcessEventJob.perform_now(event.id)

    mail = render_notification(event.notification)

    assert_equal "It's a match! on DateZA", mail.subject
    assert_includes mail.html_part.body.decoded, "You and Inga matched on DateZA."
    assert_includes mail.html_part.body.decoded, "https://www.date-za.com/matches/#{@match.public_id}"
  end

  private

  def create_member(display_name)
    user = User.create!
    membership = BrandMembership.create!(brand: @brand, user:, status: :active)
    user.identity_identifiers.create!(
      kind: :email, normalized_value: "#{SecureRandom.hex(6)}@example.com", verified_at: Time.current
    )
    Profile.create!(
      brand: @brand, user:, brand_membership: membership, display_name:,
      gender: "woman", birthdate: 28.years.ago.to_date, status: :active, visibility: :visible
    )
  end

  def message_notification(body:)
    result = Messaging::SendMessage.call(
      user: @sender.user, brand: @brand, conversation_public_id: @conversation.public_id, body:
    )
    event = NotificationEvent.find_by!(idempotency_key: "message_received:#{result.message.public_id}:#{@recipient.id}")
    Notifications::ProcessEventJob.perform_now(event.id)
    event.notification
  end

  def publish_and_materialize(message, recipient: @recipient)
    event = Notifications::EventPublisher.message_received!(message:, recipient:)
    Notifications::ProcessEventJob.perform_now(event.id)
    event.notification
  end

  def render_notification(notification)
    ProductNotificationMailer.with(
      brand_slug: @brand.slug,
      notification_type: notification.notification_type,
      notification_id: notification.id,
      recipient: "recipient@example.com",
      from_address: "DateZA <hello@dateza.test>"
    ).welcome
  end

  def attach_safe_profile_photo(profile)
    bytes = File.binread(file_fixture("profile_photo.png"))
    photo = ProfilePhoto.new(
      brand: @brand, user: profile.user, profile:, position: 0,
      status: :approved, visibility: :visible, processing_state: :pending
    )
    photo.image.attach(io: StringIO.new(bytes), filename: "original.png", content_type: "image/png")
    photo.save!
    photo.display_image.attach(io: StringIO.new(bytes), filename: "display.jpg", content_type: "image/jpeg")
    photo.update!(processing_state: :ready)
  end
end
