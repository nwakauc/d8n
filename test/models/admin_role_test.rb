require "test_helper"

class AdminRoleTest < ActiveSupport::TestCase
  test "requires a name" do
    role = AdminRole.new

    assert_not role.valid?
    assert_includes role.errors[:name], "can't be blank"
  end

  test "enforces unique active name" do
    AdminRole.create!(name: "moderator")
    duplicate = AdminRole.new(name: "moderator")

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:name], "has already been taken"
  end
end
