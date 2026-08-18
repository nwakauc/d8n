module Hooks
  # Single source of truth for Hook product/abuse limits. Everything that needs a
  # duration or an allowance reads it from here rather than sprinkling literals
  # through the domain, so tuning (or a future Plus tier) is a one-file change.
  module Policy
    # Pending Hooks expire after this window. An expired Hook can never unlock a
    # conversation (Hook#live? re-checks this regardless of the status column).
    EXPIRES_IN = 48.hours

    # Conservative V1 anti-spam ceiling: how many Hooks one sender may create per
    # rolling 24h. Deliberately low because a Hook is far more intrusive than a
    # Like. Per-pair spam is already impossible (one Hook per pair, ever), so this
    # only bounds how widely someone can spray openers.
    FREE_DAILY_LIMIT = 10
    RATE_WINDOW = 24.hours

    # Returns the sender's daily Hook allowance. Structured as a seam for a future
    # Plus tier / per-profile allowance without touching call sites; today every
    # profile gets the free limit.
    def self.daily_limit_for(_profile)
      FREE_DAILY_LIMIT
    end
  end
end
