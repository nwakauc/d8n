require "test_helper"

module Brands
  # Proves the incident class the audit flagged cannot recur: a freshly
  # deployed environment where the application boots but no BrandDomain (or
  # other persisted brand data) exists yet. Every assertion here starts from
  # a database with zero kept Brand/BrandDomain rows for the brand under
  # test — nothing here depends on an already-populated dev database.
  class FreshEnvironmentProvisioningTest < ActiveSupport::TestCase
    FakeRequest = Struct.new(:host)

    test "DateZA can be provisioned from missing brand data and resolves correctly" do
      assert_not Brand.kept.exists?(slug: "dateza")
      assert_not BrandDomain.kept.exists?(host: "dateza.test")

      brand = Provisioner.call(slug: "dateza", hosts: [ "dateza.test" ])

      result = Resolver.call(request: FakeRequest.new("dateza.test"))
      assert_equal brand, result.brand
      assert_equal :host, result.source

      assert_equal %w[ phone_password email_password ], brand.auth_methods
      assert brand.profile_option_groups.kept.exists?(key: "relationship_intent")
    end

    test "HookUs can be provisioned from missing brand data and resolves correctly" do
      assert_not Brand.kept.exists?(slug: "hookus")
      assert_not BrandDomain.kept.exists?(host: "hookus.test")

      brand = Provisioner.call(slug: "hookus", hosts: [ "hookus.test" ])

      result = Resolver.call(request: FakeRequest.new("hookus.test"))
      assert_equal brand, result.brand
      assert_equal :host, result.source

      assert_equal %w[ phone_password email_password ], brand.auth_methods
      assert brand.profile_option_groups.kept.exists?(key: "intents")
      assert brand.profile_option_groups.kept.exists?(key: "vibes")
    end

    test "rerunning provisioning for both brands is safe and leaves distinct correct mappings" do
      dateza = Provisioner.call(slug: "dateza", hosts: [ "dateza.test" ])
      hookus = Provisioner.call(slug: "hookus", hosts: [ "hookus.test" ])

      assert_no_difference [ -> { Brand.count }, -> { BrandDomain.count } ] do
        Provisioner.call(slug: "dateza", hosts: [ "dateza.test" ])
        Provisioner.call(slug: "hookus", hosts: [ "hookus.test" ])
      end

      assert_equal dateza, Resolver.call(request: FakeRequest.new("dateza.test")).brand
      assert_equal hookus, Resolver.call(request: FakeRequest.new("hookus.test")).brand
      assert_not_equal dateza, hookus
    end

    test "unsupported brand provisioning fails safely without creating partial data" do
      assert_no_difference [ -> { Brand.count }, -> { BrandDomain.count } ] do
        assert_raises(Provisioner::UnsupportedBrand) do
          Provisioner.call(slug: "unknown_brand", hosts: [ "unknown.test" ])
        end
      end

      assert_nil Resolver.call(request: FakeRequest.new("unknown.test")).brand
    end

    test "host uniqueness across brands is preserved during provisioning" do
      Provisioner.call(slug: "hookus", hosts: [ "shared.test" ])

      assert_raises(DatezaInstaller::HostConflict) do
        Provisioner.call(slug: "dateza", hosts: [ "shared.test" ])
      end
    end
  end
end
