require "test_helper"

class Admin::CapabilitiesTest < ActiveSupport::TestCase
  test "all canonical roles have explicit immutable capability sets" do
    assert_equal %w[analyst engineering founder marketing moderator operations super_admin support trust_safety],
      Admin::Capabilities::ROLE_NAMES.sort
    assert_equal Admin::Capabilities::ALL.sort, Admin::Capabilities.for_role("founder")
    assert_includes Admin::Capabilities.for_role("trust_safety"), Admin::Capabilities::REPORTS_MODERATE
    assert_not_includes Admin::Capabilities.for_role("support"), Admin::Capabilities::REPORTS_MODERATE
    assert_equal [], Admin::Capabilities.for_role("unknown")
    assert Admin::Capabilities.for_role("moderator").frozen?
  end

  test "only founder can grant super admin and founder remains bootstrap-only" do
    founder = context_for("founder")
    super_admin = context_for("super_admin")

    assert Admin::RolePolicy.grantable?(founder, "super_admin")
    assert_not Admin::RolePolicy.grantable?(super_admin, "super_admin")
    assert_not Admin::RolePolicy.grantable?(founder, "founder")
  end

  private

  def context_for(role_name)
    role = AdminRole.new(name: role_name)
    Admin::AuthorizationContext::Result.new(
      admin_user: AdminUser.new,
      assignment: AdminAssignment.new,
      role:,
      capabilities: Admin::Capabilities.for_role(role_name)
    )
  end
end
