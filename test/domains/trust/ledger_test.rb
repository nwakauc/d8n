require "test_helper"

class Trust::LedgerTest < ActiveSupport::TestCase
  setup do
    @brand = Brand.create!(slug: "date9ja", name: "Date9ja")
    @user = User.create!
  end

  test "score is 0 for a user with no ledger rows" do
    assert_equal 0, Trust::Ledger.score(user: @user, brand: @brand)
  end

  test "score sums events and non-overturned adjustments" do
    TrustEvent.create!(brand: @brand, user: @user, event_type: "realme_email_approved", points: 25, idempotency_key: "e1", occurred_at: 2.days.ago)
    TrustEvent.create!(brand: @brand, user: @user, event_type: "phone_verified", points: 50, idempotency_key: "e2", occurred_at: 1.day.ago)
    TrustAdjustment.create!(brand: @brand, user: @user, points: -20, reason_code: "policy_violation", idempotency_key: "a1", occurred_at: 1.hour.ago)

    assert_equal 55, Trust::Ledger.score(user: @user, brand: @brand)
  end

  test "an overturned adjustment does not reduce the score" do
    TrustEvent.create!(brand: @brand, user: @user, event_type: "realme_email_approved", points: 25, idempotency_key: "e1", occurred_at: 2.days.ago)
    TrustAdjustment.create!(
      brand: @brand, user: @user, points: -20, reason_code: "policy_violation",
      idempotency_key: "a1", occurred_at: 1.hour.ago, appeal_status: "overturned"
    )

    assert_equal 25, Trust::Ledger.score(user: @user, brand: @brand)
  end

  test "does not leak another brand's or user's ledger" do
    other_brand = Brand.create!(slug: "hookus", name: "HookUs")
    other_user = User.create!
    TrustEvent.create!(brand: other_brand, user: @user, event_type: "realme_email_approved", points: 25, idempotency_key: "e1", occurred_at: Time.current)
    TrustEvent.create!(brand: @brand, user: other_user, event_type: "realme_email_approved", points: 25, idempotency_key: "e2", occurred_at: Time.current)

    assert_equal 0, Trust::Ledger.score(user: @user, brand: @brand)
  end

  test "breakdown labels known event types and falls back to humanize for unknown ones" do
    TrustEvent.create!(brand: @brand, user: @user, event_type: "realme_email_approved", points: 25, idempotency_key: "e1", occurred_at: 2.days.ago)
    TrustEvent.create!(brand: @brand, user: @user, event_type: "some_future_event", points: 5, idempotency_key: "e2", occurred_at: 1.day.ago)

    breakdown = Trust::Ledger.breakdown(user: @user, brand: @brand)

    assert_equal "Email verification", breakdown.find { |e| e.fetch(:type) == "realme_email_approved" }.fetch(:label)
    assert_equal "Some future event", breakdown.find { |e| e.fetch(:type) == "some_future_event" }.fetch(:label)
    assert_equal [ 1.day.ago, 2.days.ago ].map(&:to_date), breakdown.map { |e| e.fetch(:occurred_at).to_date }
  end
end
