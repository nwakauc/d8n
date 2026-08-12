require "test_helper"

class BrandMembershipTest < ActiveSupport::TestCase
  test "allows one active membership per user and brand" do
    user = User.create!
    brand = Brand.create!(slug: "hookus", name: "HookUs")

    BrandMembership.create!(user:, brand:)
    duplicate = BrandMembership.new(user:, brand:)

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:user_id], "has already been taken"
  end

  test "allows membership reuse after soft deletion" do
    user = User.create!
    brand = Brand.create!(slug: "hookus", name: "HookUs")

    BrandMembership.create!(user:, brand:, deleted_at: Time.current)
    membership = BrandMembership.new(user:, brand:)

    assert membership.valid?
  end
end
