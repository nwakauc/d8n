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

  test "enforces one active role per admin and brand" do
    brand = Brand.create!(slug: "one-role", name: "One Role")
    admin_user = AdminUser.create!
    moderator = AdminRole.create!(name: "moderator-one-role")
    support = AdminRole.create!(name: "support-one-role")
    AdminAssignment.create!(admin_user:, brand:, admin_role: moderator)

    second = AdminAssignment.new(admin_user:, brand:, admin_role: support)

    assert_not second.valid?
    assert_includes second.errors[:admin_user_id], "already has an active role for this brand"
  end
end
