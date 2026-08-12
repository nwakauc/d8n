require "test_helper"

class OtpChallengeTest < ActiveSupport::TestCase
  test "matches codes using the stored digest" do
    brand = Brand.create!(slug: "hookus", name: "HookUs")
    challenge = OtpChallenge.create!(
      brand:,
      kind: :phone_otp,
      identifier: "27821234567",
      code_digest: OtpChallenge.digest_code("123456"),
      expires_at: 10.minutes.from_now
    )

    assert challenge.code_matches?("123456")
    assert_not challenge.code_matches?("654321")
    assert_not_equal "123456", challenge.code_digest
  end

  test "active excludes consumed and expired challenges" do
    brand = Brand.create!(slug: "hookus", name: "HookUs")
    active = OtpChallenge.create!(
      brand:,
      kind: :phone_otp,
      identifier: "27821234567",
      code_digest: OtpChallenge.digest_code("123456"),
      expires_at: 10.minutes.from_now
    )
    expired = OtpChallenge.create!(
      brand:,
      kind: :phone_otp,
      identifier: "27821234568",
      code_digest: OtpChallenge.digest_code("123456"),
      expires_at: 10.minutes.ago
    )
    consumed = OtpChallenge.create!(
      brand:,
      kind: :phone_otp,
      identifier: "27821234569",
      code_digest: OtpChallenge.digest_code("123456"),
      expires_at: 10.minutes.from_now,
      consumed_at: Time.current
    )

    assert_includes OtpChallenge.active, active
    assert_not_includes OtpChallenge.active, expired
    assert_not_includes OtpChallenge.active, consumed
  end
end
