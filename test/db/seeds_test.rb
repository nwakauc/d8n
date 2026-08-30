require "test_helper"

class SeedsTest < ActiveSupport::TestCase
  test "seeding is idempotent and creates the canonical admin roles" do
    assert_difference -> { AdminRole.count }, Admin::Capabilities::ROLE_NAMES.length do
      load Rails.root.join("db/seeds.rb")
    end

    assert_equal Admin::Capabilities::ROLE_NAMES.sort, AdminRole.kept.order(:name).pluck(:name)
    assert AdminRole.kept.all? { |role| role.description.present? }

    assert_no_difference -> { AdminRole.count } do
      load Rails.root.join("db/seeds.rb")
    end
  end
end
