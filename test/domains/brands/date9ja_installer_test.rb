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

    test "canonical production host resolves Date9ja and an unknown host resolves nothing" do
      brand = Date9jaInstaller.call(hosts: [ "api.date9ja.love" ])

      request = Struct.new(:host)
      assert_equal brand, Resolver.call(request: request.new("api.date9ja.love")).brand
      assert_nil Resolver.call(request: request.new("unknown.date9ja.love")).brand
    end

    test "installs sensitive parity groups with compatibility-visible genotype" do
      brand = Date9jaInstaller.call(hosts: [])

      sensitive = %w[ religion religion_importance tribe genotype ]
      installed = brand.profile_option_groups.kept.pluck(:key)

      assert_equal sensitive.sort, (installed & sensitive).sort
      sensitive.excluding("genotype").each do |key|
        assert brand.profile_option_groups.kept.find_by!(key:).visibility_owner_only?
      end
      assert brand.profile_option_groups.kept.find_by!(key: "genotype").visibility_public_profile?
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

    test "does not reset existing operator-owned brand state" do
      brand = Date9jaInstaller.call(hosts: [])
      brand.update!(status: :disabled, auth_methods: [ "email_password" ], profile_requirements: { "profile_fields" => [] })

      Date9jaInstaller.call(hosts: [])

      brand.reload
      assert brand.disabled?
      assert_equal [ "email_password" ], brand.auth_methods
      assert_equal [], brand.profile_requirements.fetch("profile_fields")
    end
  end
end
