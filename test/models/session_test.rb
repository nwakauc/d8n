require "test_helper"

class SessionTest < ActiveSupport::TestCase
  test "issues a raw token once and stores only the digest" do
    brand = Brand.create!(slug: "hookus", name: "HookUs")
    user = User.create!

    raw_token, session = Session.issue!(user:, brand:, device_name: "iPhone")

    assert raw_token.present?
    assert_equal Session.digest_token(raw_token), session.token_digest
    assert_not_equal raw_token, session.token_digest
    assert_equal "iPhone", session.device_name
    assert session.expires_at.future?
    assert_includes Session.active, session
  end

  test "expired sessions are not active" do
    brand = Brand.create!(slug: "hookus", name: "HookUs")
    user = User.create!
    session = Session.create!(
      user:,
      brand:,
      token_digest: Session.digest_token("old-token"),
      last_used_at: 2.days.ago,
      expires_at: 1.day.ago
    )

    assert_not_includes Session.active, session
    assert session.expired?
  end

  test "session token digests use a session-specific HMAC purpose" do
    assert_not_equal OtpChallenge.digest_code("123456"), Session.digest_token("123456")
  end
end
