module AbuseProtection
  # Generic, brand-aware, DB-backed action rate limiter. Given a product action
  # and the resolved request identity (brand, authenticated user, client IP), it
  # increments the fixed-window counter for each policy rule and reports the first
  # one exceeded, with the seconds until that window rolls.
  #
  # Storage is Postgres (RateLimitCounter), chosen to match D8N's existing
  # DB-backed throttles (auth/OTP/Hook) rather than introduce Redis or a cache
  # store the platform does not run (production Rails.cache is :null_store). The
  # atomic upsert makes it correct across multiple app nodes without coordination.
  #
  # FAIL-OPEN posture: this protects against abuse/scraping, not authentication or
  # authorization. A counter-store error must never take the dating API down, so
  # any failure here is logged and the request is ALLOWED. Security-critical
  # throttles (registration/login/recovery/OTP) are separate, remain authoritative,
  # and keep their own fail-closed, transaction-bound semantics — this layer does
  # not touch them.
  class RateLimiter
    Result = Data.define(:throttled?, :retry_after, :rule_name, :action)

    def self.call(...)
      new(...).call
    end

    def initialize(action:, brand:, user:, ip_address:, now: Time.current)
      @action = action
      @brand = brand
      @user = user
      @ip_address = ip_address.presence
      @now = now
    end

    def call
      # Resolve the policy OUTSIDE the fail-open rescue: an unknown action is a
      # programmer error (a typo that would otherwise silently disable protection),
      # so it must raise, never be swallowed as "allowed".
      rules = Policy.rules_for(action)
      evaluate(rules)
    rescue Policy::UnknownAction
      raise
    rescue StandardError => e
      # Fail OPEN: a counter-store hiccup must not take the API down. Logged only.
      Rails.logger.error("[abuse_protection] limiter_error action=#{action} error=#{e.class}")
      allowed
    end

    private

    attr_reader :action, :brand, :user, :ip_address, :now

    def evaluate(rules)
      rules.each do |rule|
        identity = identity_for(rule.scope)
        # A rule whose identity is absent (e.g. an :ip rule with no client IP, or
        # a :user rule on an unauthenticated request) cannot be attributed, so it
        # is skipped rather than bucketed under a shared blank key.
        next if identity.blank?

        window_start = rule.bucket_start(now)
        count = RateLimitCounter.increment!(
          throttle_key: throttle_key(rule:, identity:),
          window_started_at: window_start,
          expires_at: window_start + rule.window,
          now:
        )
        next if count <= rule.limit

        retry_after = [ (window_start + rule.window - now).ceil, 1 ].max
        return Result.new(true, retry_after, rule.name, action)
      end

      allowed
    end

    def identity_for(scope)
      case scope
      when :user
        "brand:#{brand.id}:user:#{user.id}" if brand && user
      when :ip
        # Platform-wide on purpose: not scoped by brand.
        "ip:#{ip_address}" if ip_address
      end
    end

    # Opaque, fixed-length key. HMAC keeps raw IPs and user ids out of the counter
    # table and bounds key length; window seconds are folded in so retuning a
    # rule's window naturally starts a fresh key space.
    def throttle_key(rule:, identity:)
      Identity::HmacDigest.call(
        purpose: "abuse-protection",
        value: "#{action}:#{rule.name}:#{rule.window.to_i}:#{identity}"
      )
    end

    def allowed
      Result.new(false, nil, nil, action)
    end
  end
end
