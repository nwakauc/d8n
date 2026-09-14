require "test_helper"

class Identity::RealmeAssertionsTest < ActiveSupport::TestCase
  setup do
    @brand = Brand.create!(slug: "hookus-realme", name: "HookUs")
    @user = User.create!
  end

  test "returns nothing when the user has no assertions" do
    assert_equal [], Identity::RealmeAssertions.call(user: @user, brand: @brand)
  end

  test "surfaces the latest assertion per canonical check type" do
    VerificationAssertion.create!(
      brand: @brand, user: @user, source_type: "verification_check", source_id: "s1",
      check_type: "selfie", status: "approved"
    )
    VerificationAssertion.create!(
      brand: @brand, user: @user, source_type: "verification_check", source_id: "s2",
      check_type: "liveness", status: "rejected"
    )
    VerificationAssertion.create!(
      brand: @brand, user: @user, source_type: "verification_check", source_id: "s3",
      check_type: "gov_id", status: "unknown"
    )

    entries = Identity::RealmeAssertions.call(user: @user, brand: @brand).index_by(&:check_type)

    assert_equal "approved", entries.fetch("selfie").status
    assert_equal "rejected", entries.fetch("video").status
    assert_equal "pending", entries.fetch("government_id").status
    assert_nil entries["phone"]
  end

  test "does not leak another user's or brand's assertions" do
    other_user = User.create!
    other_brand = Brand.create!(slug: "hookus-realme-2", name: "HookUs 2")
    VerificationAssertion.create!(
      brand: @brand, user: other_user, source_type: "verification_check", source_id: "o1",
      check_type: "selfie", status: "approved"
    )
    VerificationAssertion.create!(
      brand: other_brand, user: @user, source_type: "verification_check", source_id: "o2",
      check_type: "video", status: "approved"
    )

    assert_equal [], Identity::RealmeAssertions.call(user: @user, brand: @brand)
  end
end
