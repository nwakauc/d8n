module Media
  # Selects the private Active Storage service for a brand and deployment
  # environment. Blob#service_name persists this choice, so upload signing,
  # retrieval, processing, and purge keep using the same bucket for the blob's
  # entire lifecycle.
  class StorageResolver
    ENVIRONMENTS = %w[ staging production ].freeze

    class ConfigurationError < StandardError; end

    class << self
      def service_name(brand:)
        return ActiveStorage::Blob.service.name.to_s unless Rails.configuration.x.r2_storage_enabled

        name = configured_service_name(
          brand:,
          environment: Rails.configuration.x.media_storage_environment,
          configured_brands: Rails.configuration.x.r2_brand_slugs
        )
        ActiveStorage::Blob.services.fetch(name)
        name.to_s
      rescue KeyError
        raise ConfigurationError, "Private media storage service is not configured for this brand and environment"
      end

      def configured_service_name(brand:, environment:, configured_brands:)
        environment = environment.to_s
        unless ENVIRONMENTS.include?(environment)
          raise ConfigurationError, "Private media storage environment is not configured"
        end

        slug = brand&.slug.to_s
        unless configured_brands.map(&:to_s).include?(slug)
          raise ConfigurationError, "Private media storage is not configured for this brand"
        end

        "r2_#{slug}_#{environment}".to_sym
      end

      # Existing HookUs staging blobs may retain the legacy `r2` service_name.
      # Accept it only for that exact brand/environment while new intents use the
      # brand-specific service.
      def compatible_service?(brand:, service_name:)
        expected = service_name(brand:)
        return true if service_name.to_s == expected

        Rails.configuration.x.r2_storage_enabled &&
          Rails.configuration.x.media_storage_environment == "staging" &&
          brand.slug == "hookus" && service_name.to_s == "r2"
      end
    end
  end
end
