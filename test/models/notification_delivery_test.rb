require "test_helper"

class NotificationDeliveryTest < ActiveSupport::TestCase
  test "requires a provider and recipient" do
    brand = Brand.create!(slug: "hookus", name: "HookUs")
    delivery = NotificationDelivery.new(brand:, channel: :sms, status: :pending)

    assert_not delivery.valid?
    assert_includes delivery.errors[:provider], "can't be blank"
    assert_includes delivery.errors[:recipient], "can't be blank"
  end

  test "supports SMS delivery without a user before account verification" do
    brand = Brand.create!(slug: "hookus", name: "HookUs")
    delivery = NotificationDelivery.create!(
      brand:,
      channel: :sms,
      provider: "test",
      recipient: "27821234567"
    )

    assert delivery.pending?
    assert delivery.sms?
    assert_nil delivery.user
  end
end
