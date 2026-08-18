module HookTonight
  # Single source of truth for Hook Tonight availability policy. Everything that
  # needs the availability window or the accepted intents reads it from here.
  module Policy
    # How long an activation stays live. Hook Tonight is a TEMPORARY "tonight"
    # signal, not a profile setting, so it lapses on its own. We deliberately use a
    # simple fixed duration rather than midnight/timezone machinery: the platform
    # has no per-user timezone today, and a fixed window is defensible ("the next
    # several hours"), self-expiring, and trivially correct. 6 hours comfortably
    # covers an evening while guaranteeing a forgotten activation cannot linger
    # into the next day.
    #
    # Expiry is LAZY: HookTonightState#live? re-checks this against the clock, so a
    # cleanup job (if one is ever added) is a cosmetic convenience, never a
    # correctness dependency.
    EXPIRES_IN = 6.hours

    # V1 exposes a single availability intent. Kept as an allowlist so the
    # activation request can carry `intent` (forward-compatible) without becoming a
    # questionnaire; anything outside the list is rejected rather than stored.
    DEFAULT_INTENT = "open_to_meeting".freeze
    INTENTS = [ DEFAULT_INTENT ].freeze

    class InvalidIntent < StandardError; end

    # Normalizes/validates a requested intent: blank falls back to the default, a
    # known intent passes through, anything else raises InvalidIntent (surfaced as
    # a 422 by the controller).
    def self.normalize_intent(value)
      return DEFAULT_INTENT if value.blank?

      normalized = value.to_s
      raise InvalidIntent, "unsupported intent" unless INTENTS.include?(normalized)

      normalized
    end
  end
end
