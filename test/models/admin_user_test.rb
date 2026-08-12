require "test_helper"

class AdminUserTest < ActiveSupport::TestCase
  test "defaults to active" do
    admin_user = AdminUser.create!

    assert admin_user.active?
  end
end
