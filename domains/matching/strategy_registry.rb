module Matching
  class StrategyRegistry
    class UnsupportedBrand < StandardError; end
    class UnsupportedMode < StandardError; end

    DEFAULT_MODE = "for_you".freeze

    def self.fetch(brand:, mode: nil)
      fetch_surface(brand:, mode:).strategy
    end

    def self.fetch_surface(brand:, mode: nil)
      surface = surface_for(brand:, mode:)
      strategy = surface.strategy
      return surface if surface.delivery_type == :daily_batch && strategy&.respond_to?(:rank_daily_selection)
      return surface if strategy&.production_ready?

      raise UnsupportedBrand, "matching is not configured for this brand"
    end

    def self.surface_for(brand:, mode: nil)
      contract = platform_contract(brand:)
      surface_key = if mode.to_s.present?
        "discovery.#{mode}"
      else
        contract.default_discovery_surface_key || "discovery.#{DEFAULT_MODE}"
      end
      surface = contract.surface(surface_key)
      if surface.nil?
        unless contract.capability_enabled?("discovery.surface.feed")
          raise UnsupportedBrand, "matching is not configured for this brand"
        end

        raise UnsupportedMode, "unsupported discovery mode"
      end
      unless contract.capability_enabled?(surface.delivery_capability_key)
        raise UnsupportedBrand, "matching is not configured for this brand"
      end

      surface
    end

    # Like/Pass eligibility is distinct from discovery availability. DateZA can
    # interact with profiles surfaced by Find while DateZA Discovery remains
    # deliberately unregistered.
    def self.eligibility_policy_for(brand:)
      D8n::Platform::BrandRegistry.fetch(brand:).interaction.eligibility_policy
    rescue D8n::Platform::BrandRegistry::UnsupportedBrand
      raise UnsupportedBrand, "matching interactions are not configured for this brand"
    end

    # Pair compatibility is deliberately separate from discovery ranking. A
    # brand may support compatibility in Find before it has a production
    # Discovery strategy (as DateZA does today).
    def self.compatibility_for(brand:)
      strategy = D8n::Platform::BrandRegistry.fetch(brand:).interaction.compatibility_strategy
      return strategy if strategy

      raise UnsupportedBrand, "compatibility is not configured for this brand"
    rescue D8n::Platform::BrandRegistry::UnsupportedBrand
      raise UnsupportedBrand, "compatibility is not configured for this brand"
    end

    def self.platform_contract(brand:)
      D8n::Platform::BrandRegistry.fetch(brand:)
    rescue D8n::Platform::BrandRegistry::UnsupportedBrand
      raise UnsupportedBrand, "matching is not configured for this brand"
    end
    private_class_method :platform_contract
  end
end
