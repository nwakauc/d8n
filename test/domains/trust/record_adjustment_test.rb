require "test_helper"

class Trust::RecordAdjustmentTest < ActiveSupport::TestCase
  setup do
    @brand = Brand.create!(slug: "date9ja", name: "Date9ja")
    @user = User.create!
    admin_owner = User.create!
    @admin_user = AdminUser.create!(user: admin_owner, status: :active)
  end

  test "creates a negative TrustAdjustment and an audit SecurityEvent" do
    assert_difference -> { SecurityEvent.count }, 1 do
      adjustment = Trust::RecordAdjustment.call(
        admin_user: @admin_user, brand: @brand, user: @user,
        points: -20, reason_code: "policy_violation", idempotency_key: "adj1"
      )

      assert_equal(-20, adjustment.points)
      assert_equal @admin_user, adjustment.actor_admin_user
    end
  end

  test "rejects non-negative points" do
    assert_raises(Trust::RecordAdjustment::Error) do
      Trust::RecordAdjustment.call(
        admin_user: @admin_user, brand: @brand, user: @user,
        points: 5, reason_code: "policy_violation", idempotency_key: "adj1"
      )
    end
  end

  test "is idempotent" do
    Trust::RecordAdjustment.call(admin_user: @admin_user, brand: @brand, user: @user, points: -20, reason_code: "policy_violation", idempotency_key: "adj1")
    Trust::RecordAdjustment.call(admin_user: @admin_user, brand: @brand, user: @user, points: -20, reason_code: "policy_violation", idempotency_key: "adj1")

    assert_equal 1, TrustAdjustment.where(brand: @brand, user: @user).count
  end
end
