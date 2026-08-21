require "test_helper"

module Brands
  class DatezaInstallerTest < ActiveSupport::TestCase
    test "provisions the canonical DateZA tenant and hosts idempotently" do
      assert_difference -> { Brand.count }, 1 do
        assert_difference -> { BrandDomain.count }, 1 do
          DatezaInstaller.call(hosts: [ " DateZA.Test. ", "dateza.test" ])
        end
      end

      assert_no_difference [ -> { Brand.count }, -> { BrandDomain.count }, -> { ProfileOptionGroup.count } ] do
        DatezaInstaller.call(hosts: [ "dateza.test" ])
      end

      brand = Brand.kept.find_by!(slug: "dateza")
      assert_equal "DateZA", brand.name
      assert brand.active?
      assert_equal %w[ phone_password email_password ], brand.auth_methods
      assert_equal brand, BrandDomain.kept.active.find_by!(host: "dateza.test").brand
    end

    test "does not take a host assigned to another brand" do
      hookus = Brand.create!(slug: "hookus", name: "HookUs")
      BrandDomain.create!(brand: hookus, host: "dateza.test")

      assert_raises(DatezaInstaller::HostConflict) do
        DatezaInstaller.call(hosts: [ "dateza.test" ])
      end

      assert_equal hookus, BrandDomain.kept.find_by!(host: "dateza.test").brand
      assert_not Brand.kept.exists?(slug: "dateza")
    end
  end
end
