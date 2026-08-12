require "test_helper"

class BrandTest < ActiveSupport::TestCase
  test "requires slug and name" do
    brand = Brand.new

    assert_not brand.valid?
    assert_includes brand.errors[:slug], "can't be blank"
    assert_includes brand.errors[:name], "can't be blank"
  end

  test "enforces unique active slug" do
    Brand.create!(slug: "hookus", name: "HookUs")
    duplicate = Brand.new(slug: "hookus", name: "HookUs Copy")

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:slug], "has already been taken"
  end

  test "allows slug reuse after soft deletion" do
    Brand.create!(slug: "hookus", name: "HookUs", deleted_at: Time.current)
    brand = Brand.new(slug: "hookus", name: "HookUs")

    assert brand.valid?
  end
end
