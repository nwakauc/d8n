require "test_helper"

class CurrentTest < ActiveSupport::TestCase
  test "stores request-scoped context" do
    brand = Brand.create!(slug: "hookus", name: "HookUs")

    Current.set(brand:, permissions: [ "brands.read" ]) do
      assert_equal brand, Current.brand
      assert_equal [ "brands.read" ], Current.permissions
    end
  end
end
