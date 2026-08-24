module D8n
  module Platform
    class StableDailyAllocationPolicy
      attr_reader :key, :daily_limit, :time_zone, :rollover_hour

      def initialize(key:, daily_limit:, time_zone:, rollover_hour: 0)
        @key = key.to_s.freeze
        @daily_limit = Integer(daily_limit)
        @time_zone = time_zone.to_s.freeze
        @rollover_hour = Integer(rollover_hour)

        raise ArgumentError, "allocation policy key is required" if @key.blank?
        raise ArgumentError, "daily limit must be positive" unless @daily_limit.positive?
        raise ArgumentError, "time zone is invalid" unless ActiveSupport::TimeZone[@time_zone]
        raise ArgumentError, "rollover hour is invalid" unless @rollover_hour.between?(0, 23)

        freeze
      end

      def date_at(time)
        (time.in_time_zone(time_zone) - rollover_hour.hours).to_date
      end

      def resets_at(time)
        next_date = date_at(time).next_day
        ActiveSupport::TimeZone[time_zone].local(next_date.year, next_date.month, next_date.day, rollover_hour)
      end
    end
  end
end
