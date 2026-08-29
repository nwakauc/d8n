require "test_helper"

module Brands
  class HookusInstallerTest < ActiveSupport::TestCase
    test "provisions the canonical HookUs tenant and hosts idempotently" do
      assert_difference -> { Brand.count }, 1 do
        assert_difference -> { BrandDomain.count }, 1 do
          HookusInstaller.call(hosts: [ " HookUs.Test. ", "hookus.test" ])
        end
      end

      assert_no_difference [ -> { Brand.count }, -> { BrandDomain.count }, -> { ProfileOptionGroup.count } ] do
        HookusInstaller.call(hosts: [ "hookus.test" ])
      end

      brand = Brand.kept.find_by!(slug: "hookus")
      assert_equal "HookUs", brand.name
      assert brand.active?
      assert_equal %w[ phone_password email_password ], brand.auth_methods
      assert_equal brand, BrandDomain.kept.active.find_by!(host: "hookus.test").brand
      assert_equal %w[ intents vibes ], brand.profile_completion_requirements.fetch("option_groups")
      assert brand.profile_option_groups.kept.exists?(key: "intents")
      assert brand.profile_option_groups.kept.exists?(key: "vibes")
    end

    test "does not take a host assigned to another brand" do
      dateza = Brand.create!(slug: "dateza", name: "DateZA")
      BrandDomain.create!(brand: dateza, host: "hookus.test")

      assert_raises(HookusInstaller::HostConflict) do
        HookusInstaller.call(hosts: [ "hookus.test" ])
      end

      assert_equal dateza, BrandDomain.kept.find_by!(host: "hookus.test").brand
      assert_not Brand.kept.exists?(slug: "hookus")
    end

    test "provisions with no hosts, leaving host mapping to the caller" do
      assert_difference -> { Brand.count }, 1 do
        assert_no_difference -> { BrandDomain.count } do
          HookusInstaller.call(hosts: [])
        end
      end

      assert Brand.kept.exists?(slug: "hookus")
    end
  end
end
