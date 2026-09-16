require "test_helper"

class IdentityIdentifierTest < ActiveSupport::TestCase
  test "normalizes identifier values" do
    brand = Brand.create!(slug: "hookus", name: "HookUs")
    user = User.create!
    identifier = IdentityIdentifier.create!(user:, brand:, kind: :email, normalized_value: " USER@Example.COM ")

    assert_equal "user@example.com", identifier.normalized_value
  end

  test "does not allow duplicate active identifiers within the same brand" do
    brand = Brand.create!(slug: "hookus", name: "HookUs")
    user = User.create!
    other_user = User.create!

    identifier = IdentityIdentifier.create!(user:, brand:, kind: :phone, normalized_value: "+27 82 123 4567")
    duplicate = IdentityIdentifier.new(user: other_user, brand:, kind: :phone, normalized_value: "27821234567")

    assert_equal "27821234567", identifier.normalized_value
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:normalized_value], "has already been taken"
  end

  test "does not merge accounts when identifiers overlap within the same brand" do
    brand = Brand.create!(slug: "hookus", name: "HookUs")
    user = User.create!
    other_user = User.create!

    IdentityIdentifier.create!(user:, brand:, kind: :email, normalized_value: "same@example.com")
    duplicate = IdentityIdentifier.new(user: other_user, brand:, kind: :email, normalized_value: "same@example.com")

    assert_not duplicate.valid?
    assert_equal user, IdentityIdentifier.find_by!(brand:, normalized_value: "same@example.com").user
    assert_not_equal user, other_user
  end

  test "the same identifier value is allowed independently across two different brands" do
    brand_a = Brand.create!(slug: "hookus", name: "HookUs")
    brand_b = Brand.create!(slug: "dateza", name: "DateZA")
    user_a = User.create!
    user_b = User.create!

    identifier_a = IdentityIdentifier.create!(user: user_a, brand: brand_a, kind: :email, normalized_value: "same@example.com")
    identifier_b = IdentityIdentifier.create!(user: user_b, brand: brand_b, kind: :email, normalized_value: "same@example.com")

    assert identifier_a.persisted?
    assert identifier_b.persisted?
    assert_not_equal identifier_a.user, identifier_b.user
  end
end
