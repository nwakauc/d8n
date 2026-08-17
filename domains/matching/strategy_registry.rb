module Matching
  class StrategyRegistry
    class UnsupportedBrand < StandardError; end
    class UnsupportedMode < StandardError; end

    DEFAULT_MODE = "for_you".freeze

    # Per-brand discovery modes. The default mode preserves the existing ranked
    # feed; additional modes re-rank the *same* eligible candidates (they never
    # relax eligibility). The default request (no mode) resolves to DEFAULT_MODE,
    # so existing callers stay backward compatible.
    MODES = {
      "hookus" => {
        "for_you" => Strategies::Hookus,
        "new_here" => Strategies::HookusNewHere
      }
    }.freeze
    CONTRACT_STRATEGIES = {
      "date9ja" => Strategies::Date9jaContract
    }.freeze

    def self.fetch(brand:, mode: nil)
      modes = MODES.fetch(brand.slug) do
        raise UnsupportedBrand, "matching is not configured for this brand"
      end
      strategy = modes.fetch(normalize_mode(mode)) do
        raise UnsupportedMode, "unsupported discovery mode"
      end
      return strategy if strategy.production_ready?

      raise UnsupportedBrand, "matching is not configured for this brand"
    end

    def self.contract_for(brand:)
      CONTRACT_STRATEGIES.fetch(brand.slug) do
        raise UnsupportedBrand, "matching contract is not configured for this brand"
      end
    end

    def self.normalize_mode(mode)
      mode.to_s.presence || DEFAULT_MODE
    end
    private_class_method :normalize_mode
  end
end
