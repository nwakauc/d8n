require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "defaults to active" do
    user = User.create!

    assert user.active?
  end
end
