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
  end
end
