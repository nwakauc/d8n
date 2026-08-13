module Matching
  class StrategyRegistry
    class UnsupportedBrand < StandardError; end

    STRATEGIES = {
      "hookus" => Strategies::Hookus
    }.freeze
    CONTRACT_STRATEGIES = {
      "date9ja" => Strategies::Date9jaContract
    }.freeze

    def self.fetch(brand:)
      strategy = STRATEGIES.fetch(brand.slug) do
        raise UnsupportedBrand, "matching is not configured for this brand"
      end
      return strategy if strategy.production_ready?

      raise UnsupportedBrand, "matching is not configured for this brand"
    end

    def self.contract_for(brand:)
      CONTRACT_STRATEGIES.fetch(brand.slug) do
        raise UnsupportedBrand, "matching contract is not configured for this brand"
      end
    end
  end
end
