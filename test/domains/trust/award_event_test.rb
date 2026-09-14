require "test_helper"

class Trust::AwardEventTest < ActiveSupport::TestCase
  setup do
    @brand = Brand.create!(slug: "date9ja", name: "Date9ja")
    @user = User.create!
  end

  test "creates a TrustEvent" do
    event = Trust::AwardEvent.call(
      user: @user, brand: @brand, event_type: "realme_email_approved", points: 25, idempotency_key: "k1"
    )

    assert event.persisted?
    assert_equal 25, event.points
  end

  test "is idempotent: a repeated call with the same key never double-awards" do
    Trust::AwardEvent.call(user: @user, brand: @brand, event_type: "realme_email_approved", points: 25, idempotency_key: "k1")
    Trust::AwardEvent.call(user: @user, brand: @brand, event_type: "realme_email_approved", points: 25, idempotency_key: "k1")

    assert_equal 1, TrustEvent.where(brand: @brand, user: @user).count
  end

  test "concurrent-safe: a race that hits the unique index returns the existing row instead of raising" do
    TrustEvent.create!(
      brand: @brand, user: @user, event_type: "realme_email_approved", points: 25,
      idempotency_key: "k1", occurred_at: Time.current
    )

    event = Trust::AwardEvent.call(user: @user, brand: @brand, event_type: "realme_email_approved", points: 25, idempotency_key: "k1")

    assert_equal 1, TrustEvent.where(brand: @brand, user: @user).count
    assert_equal 25, event.points
  end
end
