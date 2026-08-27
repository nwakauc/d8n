require "test_helper"

class ProductNotificationTest < ActiveSupport::TestCase
  test "rejects sensitive or undefined generic payload fields" do
    brand = Brand.create!(slug: "dateza", name: "DateZA")
    user = User.create!
    membership = BrandMembership.create!(brand:, user:, status: :active)
    event = NotificationEvent.create!(
      brand:,
      user:,
      brand_membership: membership,
      event_type: "membership_registered",
      idempotency_key: "membership_registered:sensitive-test",
      occurred_at: Time.current
    )
    notification = Notification.new(
      brand:,
      user:,
      brand_membership: membership,
      notification_event: event,
      notification_type: "dateza.welcome",
      payload: { otp: "123456", message_body: "private" }
    )

    assert_not notification.valid?
    assert_includes notification.errors[:payload], "contains unsupported fields"
  end

  test "generic product preferences never disable security or transactional email" do
    preference = NotificationPreference.new(product_email_enabled: false, push_enabled: false)

    assert_not preference.allows?(:product_email)
    assert_not preference.allows?(:push)
    assert preference.allows?(:security_email)
    assert preference.allows?(:transactional_email)
  end

  test "a D8N dating event accepts only actor/target and rejects extra or unsafe fields" do
    brand = Brand.create!(slug: "dateza", name: "DateZA")
    user = User.create!
    membership = BrandMembership.create!(brand:, user:, status: :active)
    valid_event = NotificationEvent.create!(
      brand:, user:, brand_membership: membership, event_type: "like_received",
      idempotency_key: "like_received:valid-test", occurred_at: Time.current
    )
    valid = Notification.new(
      brand:, user:, brand_membership: membership, notification_event: valid_event,
      notification_type: "dateza.like_received",
      payload: { actor: { profile_id: SecureRandom.uuid }, target: { type: "profile", id: SecureRandom.uuid } }
    )

    assert valid.valid?

    invalid_event = NotificationEvent.create!(
      brand:, user:, brand_membership: membership, event_type: "like_received",
      idempotency_key: "like_received:invalid-test", occurred_at: Time.current
    )
    invalid = Notification.new(
      brand:, user:, brand_membership: membership, notification_event: invalid_event,
      notification_type: "dateza.like_received",
      payload: {
        actor: { profile_id: SecureRandom.uuid },
        target: { type: "profile", id: SecureRandom.uuid },
        message_body: "leaked text"
      }
    )

    assert_not invalid.valid?
    assert_includes invalid.errors[:payload], "contains unsupported fields"
  end
end
