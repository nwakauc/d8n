require "test_helper"

class BrandDomainTest < ActiveSupport::TestCase
  test "normalizes host before validation" do
    brand = Brand.create!(slug: "hookus", name: "HookUs")
    domain = BrandDomain.create!(brand:, host: " HookUs.Example. ")

    assert_equal "hookus.example", domain.host
  end

  test "enforces unique active host" do
    brand = Brand.create!(slug: "hookus", name: "HookUs")
    BrandDomain.create!(brand:, host: "hookus.example")

    duplicate = BrandDomain.new(brand:, host: "HOOKUS.EXAMPLE")

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:host], "has already been taken"
  end

  test "allows host reuse after soft deletion" do
    brand = Brand.create!(slug: "hookus", name: "HookUs")
    BrandDomain.create!(brand:, host: "hookus.example", deleted_at: Time.current)

    domain = BrandDomain.new(brand:, host: "hookus.example")

    assert domain.valid?
  end
end
