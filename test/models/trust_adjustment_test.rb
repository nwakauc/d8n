require "test_helper"

class TrustAdjustmentTest < ActiveSupport::TestCase
  setup do
    @brand = Brand.create!(slug: "date9ja", name: "Date9ja")
    @user = User.create!
  end

  test "requires negative points" do
    adjustment = TrustAdjustment.new(
      brand: @brand, user: @user, points: 5, reason_code: "policy_violation",
      idempotency_key: "k1", occurred_at: Time.current
    )
    assert_not adjustment.valid?
    assert adjustment.errors[:points].present?
  end

  test "counts_toward_score? is false only once overturned" do
    adjustment = TrustAdjustment.create!(
      brand: @brand, user: @user, points: -10, reason_code: "policy_violation",
      idempotency_key: "k2", occurred_at: Time.current, appeal_status: "pending"
    )
    assert adjustment.counts_toward_score?

    adjustment.update!(appeal_status: "overturned")
    assert_not adjustment.counts_toward_score?
  end
end
