require "test_helper"

class SeedsTest < ActiveSupport::TestCase
  test "seeding is idempotent and creates only the moderator admin role" do
    assert_difference -> { AdminRole.count }, 1 do
      load Rails.root.join("db/seeds.rb")
    end

    role = AdminRole.kept.find_by!(name: "moderator")
    assert role.description.present?

    assert_no_difference -> { AdminRole.count } do
      load Rails.root.join("db/seeds.rb")
    end
  end
end
