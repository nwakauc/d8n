module Hq
  module Metrics
    # Brand-local calendar windows for HQ metrics. Week boundaries follow the
    # existing Operations analytics convention: Sunday start in Africa/Johannesburg.
    class Windows
      TIME_ZONE = "Africa/Johannesburg"

      Window = Data.define(:key, :label, :start_at, :end_at)

      def self.build(now: Time.current)
        new(now:).build
      end

      def initialize(now:)
        @now = now
        @zone = ActiveSupport::TimeZone[TIME_ZONE]
      end

      def build
        local_now = now.in_time_zone(zone)
        today_start = local_now.beginning_of_day
        yesterday_start = today_start - 1.day
        yesterday_end = today_start

        {
          today: window("today", "Today", today_start, local_now),
          yesterday: window("yesterday", "Previous day", yesterday_start, yesterday_end),
          last_7d: window("last_7d", "Last 7 days", local_now - 7.days, local_now),
          previous_7d: window("previous_7d", "Previous 7 days", local_now - 14.days, local_now - 7.days),
          last_30d: window("last_30d", "Last 30 days", local_now - 30.days, local_now),
          previous_30d: window("previous_30d", "Previous 30 days", local_now - 60.days, local_now - 30.days)
        }
      end

      def metadata(windows)
        windows.transform_values do |window|
          {
            label: window.label,
            start_at: window.start_at.utc.iso8601,
            end_at: window.end_at.utc.iso8601
          }
        end
      end

      private

      attr_reader :now, :zone

      def window(key, label, start_at, end_at)
        Window.new(key:, label:, start_at:, end_at:)
      end
    end
  end
end
