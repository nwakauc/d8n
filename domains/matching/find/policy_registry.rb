module Matching
  module Find
    class PolicyRegistry
      class UnsupportedBrand < StandardError; end

      def self.fetch(brand:)
        policy = surface_for(brand:).policy
        return policy if policy

        raise UnsupportedBrand, "Find is not configured for this brand"
      rescue D8n::Platform::BrandRegistry::UnsupportedBrand
        raise UnsupportedBrand, "Find is not configured for this brand"
      end


      def self.surface_for(brand:)
        contract = D8n::Platform::BrandRegistry.fetch(brand:)
        contract.surface("discovery.find") || raise(UnsupportedBrand, "Find is not configured for this brand")
      rescue D8n::Platform::BrandRegistry::UnsupportedBrand
        raise UnsupportedBrand, "Find is not configured for this brand"
      end
    end
  end
end
