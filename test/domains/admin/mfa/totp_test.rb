require "test_helper"

class Admin::Mfa::TotpTest < ActiveSupport::TestCase
  test "generates and verifies a six-digit TOTP without exposing the secret" do
    secret = Admin::Mfa::Totp.generate_secret
    at = Time.utc(2026, 8, 29, 12, 0, 0)
    code = Admin::Mfa::Totp.code_at(secret:, counter: at.to_i / Admin::Mfa::Totp::PERIOD)

    assert_match(/\A[A-Z2-7]+\z/, secret)
    assert_match(/\A\d{6}\z/, code)
    assert Admin::Mfa::Totp.valid?(secret:, code:, at:)
    assert_not Admin::Mfa::Totp.valid?(secret:, code: "000000", at:)
  end

  test "recovery codes are one-time and stored only as digests" do
    admin = AdminUser.create!(user: User.create!, status: :active)
    codes = Admin::Mfa::RecoveryCodes.generate
    credential = AdminMfaCredential.create!(
      admin_user: admin,
      status: :active,
      secret: Admin::Mfa::Totp.generate_secret,
      confirmed_at: Time.current,
      recovery_code_digests: codes.map { |code| Admin::Mfa::RecoveryCodes.digest(code) }
    )

    assert_not_includes credential.recovery_code_digests, codes.first
    assert Admin::Mfa::RecoveryCodes.consume!(credential:, code: codes.first)
    assert_not Admin::Mfa::RecoveryCodes.consume!(credential:, code: codes.first)
    assert_equal Admin::Mfa::RecoveryCodes::COUNT - 1, credential.reload.recovery_code_digests.length
  end
end
