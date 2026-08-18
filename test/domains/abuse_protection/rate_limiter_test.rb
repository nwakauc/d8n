require "test_helper"

module AbuseProtection
  class RateLimiterTest < ActiveSupport::TestCase
    setup do
      @brand = Brand.create!(slug: "hookus", name: "HookUs")
      @other_brand = Brand.create!(slug: "date9ja", name: "Date9ja")
      @user = User.create!
      @other_user = User.create!
    end

    def limit(action:, brand: @brand, user: @user, ip: "1.1.1.1", now: Time.current)
      RateLimiter.call(action:, brand:, user:, ip_address: ip, now:)
    end

    test "allows requests up to the burst limit then throttles with a positive retry_after" do
      rule = Policy.rules_for(:send_message).first # burst
      now = Time.zone.at(1_000)

      rule.limit.times do |i|
        assert_not limit(action: :send_message, now:).throttled?, "request #{i + 1} should be allowed"
      end

      result = limit(action: :send_message, now:)
      assert result.throttled?
      assert_equal "burst", result.rule_name
      assert result.retry_after.positive?
      assert_operator result.retry_after, :<=, rule.window.to_i
    end

    test "user scope is isolated per brand so one brand cannot exhaust another" do
      rule = Policy.rules_for(:send_message).first
      now = Time.zone.at(2_000)

      (rule.limit + 5).times { limit(action: :send_message, brand: @brand, now:) }
      assert limit(action: :send_message, brand: @brand, now:).throttled?

      # Same user, different brand: a separate counter, unaffected.
      assert_not limit(action: :send_message, brand: @other_brand, now:).throttled?
    end

    test "user scope is isolated per user" do
      rule = Policy.rules_for(:send_message).first
      now = Time.zone.at(3_000)

      (rule.limit + 5).times { limit(action: :send_message, user: @user, now:) }
      assert limit(action: :send_message, user: @user, now:).throttled?
      assert_not limit(action: :send_message, user: @other_user, now:).throttled?
    end

    test "the window rolls: a later bucket starts fresh" do
      rule = Policy.rules_for(:send_message).first
      base = Time.zone.at(4_000)

      (rule.limit + 1).times { limit(action: :send_message, now: base) }
      assert limit(action: :send_message, now: base).throttled?

      later = base + rule.window + 1.second
      assert_not limit(action: :send_message, now: later).throttled?
    end

    test "ip scope applies platform-wide across brands and users" do
      # report_profile carries an :ip rule. Drive it purely via the IP scope by
      # spreading requests across many users so no per-user rule trips first.
      ip_rule = Policy.rules_for(:report_profile).find { |r| r.scope == :ip }
      now = Time.zone.at(5_000)

      ip_rule.limit.times do
        user = User.create!
        limit(action: :report_profile, brand: @brand, user:, ip: "9.9.9.9", now:)
      end

      throttled = limit(action: :report_profile, brand: @other_brand, user: User.create!, ip: "9.9.9.9", now:)
      assert throttled.throttled?, "the platform-wide IP ceiling should trip regardless of brand/user"
      assert_equal "ip", throttled.rule_name
    end

    test "rules with an unresolvable identity are skipped rather than shared under a blank key" do
      # No user => the :user rules cannot attribute; no IP => the :ip rule cannot.
      # With neither, nothing is counted and the request is allowed.
      result = RateLimiter.call(action: :report_profile, brand: @brand, user: nil, ip_address: nil)
      assert_not result.throttled?
      assert_equal 0, RateLimitCounter.count
    end

    test "fails open (allows) when the counter store raises" do
      singleton = RateLimitCounter.singleton_class
      original = RateLimitCounter.method(:increment!).unbind
      singleton.define_method(:increment!) { |**| raise ActiveRecord::StatementInvalid, "boom" }
      begin
        result = limit(action: :discovery)
        assert_not result.throttled?, "a counter-store failure must fail open, not throttle"
      ensure
        singleton.define_method(:increment!, original)
      end
    end

    test "unknown actions raise so a typo cannot silently disable protection" do
      assert_raises(Policy::UnknownAction) { limit(action: :nope) }
    end

    test "profile_write is a shared bucket across profile mutation surfaces" do
      # Every profile-mutation controller passes the same :profile_write action,
      # so they share one counter by design.
      rule = Policy.rules_for(:profile_write).first
      now = Time.zone.at(6_000)

      (rule.limit + 1).times { limit(action: :profile_write, now:) }
      assert limit(action: :profile_write, now:).throttled?
    end
  end
end
