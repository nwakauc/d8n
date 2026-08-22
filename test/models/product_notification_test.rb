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
end
