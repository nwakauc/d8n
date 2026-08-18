# Generic abuse-protection entrypoint for controllers. Include once in
# ApplicationController; guard an action with a before_action declared AFTER
# authentication so the enforcement order is:
#
#   authenticate -> resolve identity -> THROTTLE -> authorize -> validate -> act
#
# Throttling runs after authentication (so the counter is attributed to a real
# brand+user identity, not a blank key) but before the heavier authorization,
# validation, and domain work, so a flood is rejected cheaply. Domain-specific
# throttles that already exist (Hook's rolling daily allowance, auth/OTP) are
# authoritative and intentionally NOT routed through here.
module RateLimitable
  extend ActiveSupport::Concern

  private

  # Returns false and renders a 429 when the action is throttled (which halts the
  # before_action chain), true otherwise.
  def enforce_rate_limit!(action)
    result = AbuseProtection::RateLimiter.call(
      action:,
      brand: Current.brand,
      user: Current.user,
      ip_address: request.remote_ip
    )
    return true unless result.throttled?

    log_rate_limited(result)
    render_rate_limited(result.retry_after)
    false
  end

  # Standardised, brand-agnostic 429. Uses the platform's existing flat error
  # envelope (`{ "error": "rate_limited" }`) — deliberately generic so it never
  # leaks the counter key, threshold, identity, or storage details. Hook keeps
  # its distinct `hook_rate_limited` code; this is only for the generic layer.
  def render_rate_limited(retry_after)
    response.set_header("Retry-After", retry_after.to_s) if retry_after
    render json: { error: "rate_limited" }, status: :too_many_requests
  end

  # Operational telemetry only — NOT a durable SecurityEvent (a throttled
  # discovery scroll is not a security incident). Carries no PII, no message
  # content, no raw identifier: just the action, matched rule, brand, whether the
  # caller was authenticated, and the request id for correlation.
  def log_rate_limited(result)
    Rails.logger.warn(
      "[abuse_protection] throttled action=#{result.action} rule=#{result.rule_name} " \
        "brand=#{Current.brand&.id.inspect} authenticated=#{Current.user.present?} " \
        "retry_after=#{result.retry_after} request_id=#{request.request_id}"
    )
  end
end
