module Matching
  class StrategyRegistry
    class UnsupportedBrand < StandardError; end

    STRATEGIES = {
      "hookus" => Strategies::Hookus
    }.freeze

    def self.fetch(brand:)
      STRATEGIES.fetch(brand.slug) do
        raise UnsupportedBrand, "matching is not configured for this brand"
      end
    end
  end
end
