require "test_helper"

module Brands
  class ProvisionerTest < ActiveSupport::TestCase
    test "dispatches dateza to Brands::DatezaInstaller" do
      brand = Provisioner.call(slug: "dateza", hosts: [ "dateza.test" ])

      assert_equal "dateza", brand.slug
      assert_equal brand, BrandDomain.kept.find_by!(host: "dateza.test").brand
    end

    test "dispatches hookus to Brands::HookusInstaller" do
      brand = Provisioner.call(slug: "hookus", hosts: [ "hookus.test" ])

      assert_equal "hookus", brand.slug
      assert_equal brand, BrandDomain.kept.find_by!(host: "hookus.test").brand
    end

    test "accepts a symbol slug" do
      brand = Provisioner.call(slug: :hookus, hosts: [])

      assert_equal "hookus", brand.slug
    end

    test "rerunning provisioning through the registry is idempotent" do
      Provisioner.call(slug: "dateza", hosts: [ "dateza.test" ])

      assert_no_difference [ -> { Brand.count }, -> { BrandDomain.count } ] do
        Provisioner.call(slug: "dateza", hosts: [ "dateza.test" ])
      end
    end

    test "dispatches date9ja to Brands::Date9jaInstaller" do
      brand = Provisioner.call(slug: "date9ja", hosts: [ "date9ja.test" ])

      assert_equal "date9ja", brand.slug
      assert_equal brand, BrandDomain.kept.find_by!(host: "date9ja.test").brand
    end

    test "fails safely for an unsupported brand slug without touching the database" do
      assert_no_difference [ -> { Brand.count }, -> { BrandDomain.count } ] do
        assert_raises(Provisioner::UnsupportedBrand) do
          Provisioner.call(slug: "unregistered", hosts: [ "unregistered.test" ])
        end
      end
    end

    test "exposes the supported slugs" do
      assert_equal %w[ date9ja dateza hookus ], Provisioner.slugs
    end
  end
end
