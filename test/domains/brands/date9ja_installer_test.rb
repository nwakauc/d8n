require "test_helper"

module Brands
  class Date9jaInstallerTest < ActiveSupport::TestCase
    test "provisions the canonical Date9ja tenant and hosts idempotently" do
      assert_difference -> { Brand.count }, 1 do
        assert_difference -> { BrandDomain.count }, 1 do
          Date9jaInstaller.call(hosts: [ " Date9ja.Test. ", "date9ja.test" ])
        end
      end

      assert_no_difference [
        -> { Brand.count }, -> { BrandDomain.count },
        -> { ProfileOptionGroup.count }, -> { ProfileOption.count }, -> { ProfilePrompt.count }
      ] do
        Date9jaInstaller.call(hosts: [ "date9ja.test" ])
      end

      brand = Brand.kept.find_by!(slug: "date9ja")
      assert_equal "Date9ja", brand.name
      assert brand.active?
      assert_equal %w[ email_password phone_password ], brand.auth_methods
      assert_equal brand, BrandDomain.kept.active.find_by!(host: "date9ja.test").brand
      assert_equal Profiles::Date9jaProfileCatalog::REQUIRED_OPTION_GROUPS,
        brand.profile_completion_requirements.fetch("option_groups")
      assert brand.profile_option_groups.kept.exists?(key: "relationship_intent")
      assert brand.profile_option_groups.kept.exists?(key: "interests")
    end

    test "does not model any sensitive Date9ja profile field" do
      brand = Date9jaInstaller.call(hosts: [])

      sensitive = %w[ religion religion_importance ethnicity tribe denomination preferred_tribes genotype ]
      installed = brand.profile_option_groups.kept.pluck(:key)

      assert_empty(installed & sensitive, "sensitive groups must not be installed: #{(installed & sensitive).inspect}")
      %w[ enabled_profile_fields profile_fields ].each do |bucket|
        assert_empty(brand.profile_completion_requirements.fetch(bucket) & sensitive)
      end
    end

    test "does not take a host assigned to another brand" do
      hookus = Brand.create!(slug: "hookus", name: "HookUs")
      BrandDomain.create!(brand: hookus, host: "date9ja.test")

      assert_raises(Date9jaInstaller::HostConflict) do
        Date9jaInstaller.call(hosts: [ "date9ja.test" ])
      end

      assert_equal hookus, BrandDomain.kept.find_by!(host: "date9ja.test").brand
      assert_not Brand.kept.exists?(slug: "date9ja")
    end

    test "provisions with no hosts, leaving host mapping to the caller" do
      assert_difference -> { Brand.count }, 1 do
        assert_no_difference -> { BrandDomain.count } do
          Date9jaInstaller.call(hosts: [])
        end
      end

      assert Brand.kept.exists?(slug: "date9ja")
    end
  end
end
