require "test_helper"

class TrustEventTest < ActiveSupport::TestCase
  setup do
    @brand = Brand.create!(slug: "date9ja", name: "Date9ja")
    @user = User.create!
  end

  test "requires positive points" do
    event = TrustEvent.new(
      brand: @brand, user: @user, event_type: "email_verified", points: 0,
      idempotency_key: "k1", occurred_at: Time.current
    )
    assert_not event.valid?
    assert event.errors[:points].present?
  end

  test "enforces idempotency_key uniqueness within a brand" do
    TrustEvent.create!(
      brand: @brand, user: @user, event_type: "email_verified", points: 25,
      idempotency_key: "dup", occurred_at: Time.current
    )
    dup = TrustEvent.new(
      brand: @brand, user: @user, event_type: "phone_verified", points: 50,
      idempotency_key: "dup", occurred_at: Time.current
    )
    assert_not dup.valid?
  end
end
