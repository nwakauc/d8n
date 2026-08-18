module AbuseProtection
  # Keeps the fixed-window counter table bounded by deleting lapsed windows.
  # Best-effort: the limiter's correctness never depends on this running, because
  # a lapsed bucket simply stops being consulted once its window rolls. Scheduled
  # via config/recurring.yml.
  class PurgeRateLimitCountersJob < ApplicationJob
    queue_as :default

    def perform
      RateLimitCounter.purge_expired
    end
  end
end
