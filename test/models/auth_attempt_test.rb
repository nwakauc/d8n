require "test_helper"

class AuthAttemptTest < ActiveSupport::TestCase
  test "can record failed attempt before a user exists" do
    brand = Brand.create!(slug: "hookus", name: "HookUs")
    attempt = AuthAttempt.create!(
      brand:,
      kind: :phone_otp,
      result: :failed,
      identifier: "+27821234567",
      ip_address: "127.0.0.1"
    )

    assert attempt.failed?
    assert_nil attempt.user
  end

  test "requires identifier" do
    attempt = AuthAttempt.new(kind: :phone_otp, result: :failed)

    assert_not attempt.valid?
    assert_includes attempt.errors[:identifier], "can't be blank"
  end
end
