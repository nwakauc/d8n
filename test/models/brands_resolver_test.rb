require "test_helper"

module Brands
  class ResolverTest < ActiveSupport::TestCase
    Request = Data.define(:host)

    test "resolves active brand by host" do
      brand = Brand.create!(slug: "hookus", name: "HookUs")
      BrandDomain.create!(brand:, host: "hookus.example")

      result = Resolver.call(request: Request.new("HookUs.Example"))

      assert_equal brand, result.brand
      assert_equal :host, result.source
    end

    test "does not resolve disabled domains" do
      brand = Brand.create!(slug: "hookus", name: "HookUs")
      BrandDomain.create!(brand:, host: "hookus.example", status: :disabled)

      result = Resolver.call(request: Request.new("hookus.example"))

      assert_nil result.brand
      assert_nil result.source
    end

    test "does not resolve disabled or deleted brands" do
      disabled_brand = Brand.create!(slug: "hookus", name: "HookUs", status: :disabled)
      deleted_brand = Brand.create!(slug: "date9ja", name: "Date9ja", deleted_at: Time.current)
      BrandDomain.create!(brand: disabled_brand, host: "hookus.example")
      BrandDomain.create!(brand: deleted_brand, host: "date9ja.example")

      disabled_result = Resolver.call(request: Request.new("hookus.example"))
      deleted_result = Resolver.call(request: Request.new("date9ja.example"))

      assert_nil disabled_result.brand
      assert_nil deleted_result.brand
    end
  end
end
