require "test_helper"

module D8n
  module Platform
    class StableDailyAllocationPolicyTest < ActiveSupport::TestCase
      test "uses the configured timezone for allocation date and rollover" do
        johannesburg = StableDailyAllocationPolicy.new(key: "za", daily_limit: 10, time_zone: "Africa/Johannesburg")
        new_york = StableDailyAllocationPolicy.new(key: "us", daily_limit: 4, time_zone: "America/New_York")
        instant = Time.utc(2026, 8, 21, 22, 0, 0)

        assert_equal Date.new(2026, 8, 22), johannesburg.date_at(instant)
        assert_equal "2026-08-23T00:00:00+02:00", johannesburg.resets_at(instant).iso8601
        assert_equal Date.new(2026, 8, 21), new_york.date_at(instant)
        assert_equal "2026-08-22T00:00:00-04:00", new_york.resets_at(instant).iso8601
        assert_equal 4, new_york.daily_limit
      end

      test "supports a configured non-midnight rollover without engine changes" do
        policy = StableDailyAllocationPolicy.new(
          key: "night_shift", daily_limit: 6, time_zone: "Africa/Johannesburg", rollover_hour: 4
        )

        assert_equal Date.new(2026, 8, 21), policy.date_at(Time.utc(2026, 8, 22, 1, 59, 59))
        assert_equal Date.new(2026, 8, 22), policy.date_at(Time.utc(2026, 8, 22, 2, 0, 0))
        assert_equal "2026-08-23T04:00:00+02:00", policy.resets_at(Time.utc(2026, 8, 22, 2)).iso8601
      end

      test "fails fast for invalid configuration" do
        assert_raises(ArgumentError) do
          StableDailyAllocationPolicy.new(key: "bad", daily_limit: 0, time_zone: "UTC")
        end
        assert_raises(ArgumentError) do
          StableDailyAllocationPolicy.new(key: "bad", daily_limit: 1, time_zone: "Nowhere/Invalid")
        end
        assert_raises(ArgumentError) do
          StableDailyAllocationPolicy.new(key: "bad", daily_limit: 1, time_zone: "UTC", rollover_hour: 24)
        end
      end
    end
  end
end
