require "test_helper"

module Media
  class StorageResolverTest < ActiveSupport::TestCase
    test "resolves HookUs and DateZA independently in staging" do
      configured = %w[ hookus dateza ]

      assert_equal :r2_hookus_staging,
        StorageResolver.configured_service_name(
          brand: Brand.new(slug: "hookus"), environment: "staging", configured_brands: configured
        )
      assert_equal :r2_dateza_staging,
        StorageResolver.configured_service_name(
          brand: Brand.new(slug: "dateza"), environment: "staging", configured_brands: configured
        )
    end

    test "production cannot accidentally resolve a staging service" do
      configured = %w[ hookus dateza ]

      assert_equal :r2_hookus_production,
        StorageResolver.configured_service_name(
          brand: Brand.new(slug: "hookus"), environment: "production", configured_brands: configured
        )
      assert_equal :r2_dateza_production,
        StorageResolver.configured_service_name(
          brand: Brand.new(slug: "dateza"), environment: "production", configured_brands: configured
        )
    end

    test "unknown and unconfigured brands fail closed" do
      error = assert_raises(StorageResolver::ConfigurationError) do
        StorageResolver.configured_service_name(
          brand: Brand.new(slug: "unknown"), environment: "staging", configured_brands: %w[ hookus dateza ]
        )
      end

      assert_equal "Private media storage is not configured for this brand", error.message
    end

    test "unknown deployment environments fail closed" do
      assert_raises(StorageResolver::ConfigurationError) do
        StorageResolver.configured_service_name(
          brand: Brand.new(slug: "hookus"), environment: "development", configured_brands: %w[ hookus ]
        )
      end
    end

    test "local storage behavior remains unchanged when R2 is disabled" do
      assert_not Rails.configuration.x.r2_storage_enabled
      assert_equal ActiveStorage::Blob.service.name.to_s,
        StorageResolver.service_name(brand: Brand.new(slug: "hookus"))
    end
  end
end
