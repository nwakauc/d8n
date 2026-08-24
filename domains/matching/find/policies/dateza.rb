module Matching
  module Find
    module Policies
      class Dateza
        KEY = "dateza_find_v1"
        TIME_ZONE = "Africa/Johannesburg"
        DAILY_LIMIT = 10

        class << self
          def key = KEY
          def daily_limit(_membership) = DAILY_LIMIT
          def date_at(time)
            time.in_time_zone(TIME_ZONE).to_date
          end

          def resets_at(time)
            next_date = date_at(time).next_day
            ActiveSupport::TimeZone[TIME_ZONE].local(next_date.year, next_date.month, next_date.day)
          end

          def rank(scope)
            scope.order(created_at: :desc, public_id: :desc)
          end
        end
      end
    end
  end
end
