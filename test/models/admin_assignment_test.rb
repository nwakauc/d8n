require "test_helper"

class AdminAssignmentTest < ActiveSupport::TestCase
  test "keeps staff access separate from consumer brand membership" do
    brand = Brand.create!(slug: "hookus", name: "HookUs")
    role = AdminRole.create!(name: "moderator")
    admin_user = AdminUser.create!

    assignment = AdminAssignment.create!(admin_user:, brand:, admin_role: role)

    assert_equal brand, assignment.brand
    assert_equal admin_user, assignment.admin_user
    assert_equal role, assignment.admin_role
    assert_empty BrandMembership.where(brand:)
  end

  test "enforces unique active assignment per admin brand and role" do
    brand = Brand.create!(slug: "hookus", name: "HookUs")
    role = AdminRole.create!(name: "moderator")
    admin_user = AdminUser.create!

    AdminAssignment.create!(admin_user:, brand:, admin_role: role)
    duplicate = AdminAssignment.new(admin_user:, brand:, admin_role: role)

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:admin_user_id], "has already been taken"
  end
end
