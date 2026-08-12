require "test_helper"

class IdentityIdentifierTest < ActiveSupport::TestCase
  test "normalizes identifier values" do
    user = User.create!
    identifier = IdentityIdentifier.create!(user:, kind: :email, normalized_value: " USER@Example.COM ")

    assert_equal "user@example.com", identifier.normalized_value
  end

  test "does not allow duplicate active identifiers" do
    user = User.create!
    other_user = User.create!

    IdentityIdentifier.create!(user:, kind: :phone, normalized_value: "+27821234567")
    duplicate = IdentityIdentifier.new(user: other_user, kind: :phone, normalized_value: "+27821234567")

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:normalized_value], "has already been taken"
  end

  test "does not merge accounts when identifiers overlap" do
    user = User.create!
    other_user = User.create!

    IdentityIdentifier.create!(user:, kind: :email, normalized_value: "same@example.com")
    duplicate = IdentityIdentifier.new(user: other_user, kind: :email, normalized_value: "same@example.com")

    assert_not duplicate.valid?
    assert_equal user, IdentityIdentifier.find_by!(normalized_value: "same@example.com").user
    assert_not_equal user, other_user
  end
end
