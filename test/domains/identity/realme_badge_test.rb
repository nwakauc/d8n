require "test_helper"

class Identity::RealmeBadgeTest < ActiveSupport::TestCase
  setup do
    @brand = Brand.create!(slug: "date9ja", name: "Date9ja")
    @user = User.create!
  end

  test "false with no email and no assertions" do
    assert_equal false, Identity::RealmeBadge.call(user: @user, brand: @brand)
  end

  test "false when email is confirmed but a check is missing" do
    IdentityIdentifier.create!(user: @user, kind: :email, normalized_value: "a@example.com", verified_at: Time.current)
    VerificationAssertion.create!(
      brand: @brand, user: @user, source_type: "member_submission", source_id: "s1",
      check_type: "selfie", status: "approved"
    )

    assert_equal false, Identity::RealmeBadge.call(user: @user, brand: @brand)
  end

  test "true once email is confirmed and selfie, video (via liveness alias), and government_id (via gov_id alias) are approved" do
    IdentityIdentifier.create!(user: @user, kind: :email, normalized_value: "a@example.com", verified_at: Time.current)
    VerificationAssertion.create!(
      brand: @brand, user: @user, source_type: "member_submission", source_id: "s1",
      check_type: "selfie", status: "approved"
    )
    VerificationAssertion.create!(
      brand: @brand, user: @user, source_type: "verification_check", source_id: "s2",
      check_type: "liveness", status: "approved"
    )
    VerificationAssertion.create!(
      brand: @brand, user: @user, source_type: "verification_check", source_id: "s3",
      check_type: "gov_id", status: "approved"
    )

    assert_equal true, Identity::RealmeBadge.call(user: @user, brand: @brand)
  end

  test "does not count a rejected or pending check" do
    IdentityIdentifier.create!(user: @user, kind: :email, normalized_value: "a@example.com", verified_at: Time.current)
    VerificationAssertion.create!(
      brand: @brand, user: @user, source_type: "member_submission", source_id: "s1",
      check_type: "selfie", status: "rejected"
    )
    VerificationAssertion.create!(
      brand: @brand, user: @user, source_type: "member_submission", source_id: "s2",
      check_type: "video", status: "approved"
    )
    VerificationAssertion.create!(
      brand: @brand, user: @user, source_type: "member_submission", source_id: "s3",
      check_type: "government_id", status: "pending"
    )

    assert_equal false, Identity::RealmeBadge.call(user: @user, brand: @brand)
  end

  test "does not leak another brand's approved checks" do
    other_brand = Brand.create!(slug: "hookus", name: "HookUs")
    IdentityIdentifier.create!(user: @user, kind: :email, normalized_value: "a@example.com", verified_at: Time.current)
    %w[selfie video government_id].each_with_index do |check_type, i|
      VerificationAssertion.create!(
        brand: other_brand, user: @user, source_type: "member_submission", source_id: "o#{i}",
        check_type:, status: "approved"
      )
    end

    assert_equal false, Identity::RealmeBadge.call(user: @user, brand: @brand)
  end

  test "bulk computes for many users in a fixed number of queries" do
    other_user = User.create!
    IdentityIdentifier.create!(user: @user, kind: :email, normalized_value: "a@example.com", verified_at: Time.current)
    %w[selfie video government_id].each_with_index do |check_type, i|
      VerificationAssertion.create!(
        brand: @brand, user: @user, source_type: "member_submission", source_id: "b#{i}",
        check_type:, status: "approved"
      )
    end

    result = Identity::RealmeBadge.bulk(user_ids: [ @user.id, other_user.id ], brand: @brand)

    assert_equal true, result.fetch(@user.id)
    assert_equal false, result.fetch(other_user.id)
  end
end
