require "test_helper"

class Identity::VerificationVerifierTrustAwardTest < ActiveSupport::TestCase
  setup do
    @brand = Brand.create!(slug: "date9ja", name: "Date9ja")
    @user = User.create!
  end

  test "awards realme_email_approved points on successful email verification" do
    identifier = @user.identity_identifiers.create!(kind: :email, normalized_value: "ada@example.com")
    challenge = create_challenge(identifier:, kind: "email_verification")

    result = Identity::VerificationVerifier.call(user: @user, brand: @brand, kind: "email", code: "123456")

    assert result.success?
    event = TrustEvent.find_by(brand: @brand, user: @user, event_type: "realme_email_approved")
    assert event.present?
    assert_equal 25, event.points
  end

  test "awards realme_phone_approved points on successful phone verification" do
    identifier = @user.identity_identifiers.create!(kind: :phone, normalized_value: "+15551234567")
    create_challenge(identifier:, kind: "phone_verification")

    Identity::VerificationVerifier.call(user: @user, brand: @brand, kind: "phone", code: "123456")

    assert_equal 50, TrustEvent.find_by(brand: @brand, user: @user, event_type: "realme_phone_approved").points
  end

  test "does not double-award on a second verify call for an already-verified identifier" do
    identifier = @user.identity_identifiers.create!(kind: :email, normalized_value: "ada@example.com")
    create_challenge(identifier:, kind: "email_verification")
    Identity::VerificationVerifier.call(user: @user, brand: @brand, kind: "email", code: "123456")

    create_challenge(identifier:, kind: "email_verification")
    Identity::VerificationVerifier.call(user: @user, brand: @brand, kind: "email", code: "123456")

    assert_equal 1, TrustEvent.where(brand: @brand, user: @user, event_type: "realme_email_approved").count
  end

  private

  def create_challenge(identifier:, kind:)
    OtpChallenge.create!(
      brand: @brand, identity_identifier: identifier, kind:,
      identifier: identifier.normalized_value, code_digest: OtpChallenge.digest_code("123456"),
      expires_at: 10.minutes.from_now, metadata: { purpose: "identifier_verification" }
    )
  end
end
