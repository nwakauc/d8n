require "test_helper"

class RateLimitCounterTest < ActiveSupport::TestCase
  test "increment! inserts then atomically increments the same bucket" do
    window = Time.zone.at(0)
    expires = window + 1.hour

    assert_equal 1, RateLimitCounter.increment!(throttle_key: "k", window_started_at: window, expires_at: expires)
    assert_equal 2, RateLimitCounter.increment!(throttle_key: "k", window_started_at: window, expires_at: expires)
    assert_equal 3, RateLimitCounter.increment!(throttle_key: "k", window_started_at: window, expires_at: expires)

    counter = RateLimitCounter.find_by!(throttle_key: "k", window_started_at: window)
    assert_equal 3, counter.count
  end

  test "distinct keys and windows are independent buckets" do
    window_a = Time.zone.at(0)
    window_b = Time.zone.at(10)
    expires = 1.hour.from_now

    RateLimitCounter.increment!(throttle_key: "k", window_started_at: window_a, expires_at: expires)
    RateLimitCounter.increment!(throttle_key: "other", window_started_at: window_a, expires_at: expires)
    RateLimitCounter.increment!(throttle_key: "k", window_started_at: window_b, expires_at: expires)

    assert_equal 1, RateLimitCounter.find_by(throttle_key: "k", window_started_at: window_a).count
    assert_equal 1, RateLimitCounter.find_by(throttle_key: "other", window_started_at: window_a).count
    assert_equal 1, RateLimitCounter.find_by(throttle_key: "k", window_started_at: window_b).count
  end

  test "purge_expired removes only lapsed windows" do
    now = Time.current
    RateLimitCounter.create!(throttle_key: "stale", window_started_at: now - 2.hours, expires_at: now - 1.hour, count: 5)
    live = RateLimitCounter.create!(throttle_key: "live", window_started_at: now, expires_at: now + 1.hour, count: 5)

    RateLimitCounter.purge_expired(now:)

    assert_not RateLimitCounter.exists?(throttle_key: "stale")
    assert RateLimitCounter.exists?(id: live.id)
  end
end
