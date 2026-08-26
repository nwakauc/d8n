module Hooks
  # Single source of truth for D8N Opener product/abuse limits. Everything that
  # needs a duration or an allowance reads it from here rather than sprinkling
  # literals through the domain. Numbers are brand-configurable (see
  # BrandContract::OpenerConfiguration) — HookUs and DateZA currently share the
  # same defaults, but tuning one brand independently is a config change, not a
  # code change.
  module Policy
    # Fallback defaults for a brand with no explicit opener configuration (should
    # not happen for a brand with match.hook/match.opener enabled — BrandContract
    # requires one — but keeps this module safe to call defensively).
    EXPIRES_IN = 48.hours
    FREE_DAILY_LIMIT = 10
    DEFAULT = D8n::Platform::BrandContract::OpenerConfiguration.new(
      catalog_required: false, daily_limit: FREE_DAILY_LIMIT, expires_in: EXPIRES_IN
    )

    # Rolling window over which `daily_limit_for` counts recent sends. A fixed
    # engine constant (not brand-configurable) — "daily" inherently means 24h.
    RATE_WINDOW = 24.hours

    def self.config_for(brand)
      D8n::Platform::BrandRegistry.fetch(brand:).opener || DEFAULT
    rescue D8n::Platform::BrandRegistry::UnsupportedBrand
      DEFAULT
    end

    # Structured as a seam for a future Plus tier / per-profile allowance without
    # touching call sites; today every profile gets its brand's free limit.
    def self.daily_limit_for(profile)
      config_for(profile.brand).daily_limit
    end

    def self.expires_in(brand)
      config_for(brand).expires_in
    end

    def self.catalog_required?(brand)
      config_for(brand).catalog_required
    end
  end
end
