require "test_helper"

module Matching
  module Find
    class DatezaDayPolicyTest < ActiveSupport::TestCase
      test "uses Johannesburg midnight for the DateZA day and reset" do
        before_midnight = Time.utc(2026, 8, 21, 21, 59, 59)
        at_midnight = Time.utc(2026, 8, 21, 22, 0, 0)

        assert_equal Date.new(2026, 8, 21), Policies::Dateza.date_at(before_midnight)
        assert_equal Date.new(2026, 8, 22), Policies::Dateza.date_at(at_midnight)
        assert_equal "2026-08-22T00:00:00+02:00", Policies::Dateza.resets_at(before_midnight).iso8601
      end
    end
  end
end
