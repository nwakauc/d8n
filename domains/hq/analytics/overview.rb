module Hq
  module Analytics
    # Read-only, brand-scoped overview for the Operations dashboard. These
    # metrics deliberately use the canonical current definitions in METRICS.md:
    # registrations come from kept BrandMembership rows and activity comes
    # from distinct users with a Session last used in the requested window.
    class Overview
      TIME_ZONE = "Africa/Johannesburg"

      Result = Data.define(
        :brand, :generated_at, :time_zone,
        :signups_today, :signups_this_week, :signups_this_month,
        :active_today, :active_7d, :active_30d,
        :gender_split, :total_registered_members
      )

      def self.call(brand:, now: Time.current)
        new(brand:, now:).call
      end

      def initialize(brand:, now:)
        @brand = brand
        @now = now
        @zone = ActiveSupport::TimeZone[TIME_ZONE]
      end

      def call
        local_now = now.in_time_zone(zone)
        today_start = local_now.beginning_of_day
        week_start = local_now.beginning_of_week(:sunday)
        month_start = local_now.beginning_of_month

        Result.new(
          brand: brand.slug,
          generated_at: now,
          time_zone: TIME_ZONE,
          signups_today: signup_count(today_start),
          signups_this_week: signup_count(week_start),
          signups_this_month: signup_count(month_start),
          active_today: active_count(today_start),
          active_7d: active_count(now - 7.days),
          active_30d: active_count(now - 30.days),
          gender_split: gender_split,
          total_registered_members: BrandMembership.kept.where(brand:).distinct.count(:user_id)
        )
      end

      private

      attr_reader :brand, :now, :zone

      def signup_count(start_time)
        BrandMembership.kept.where(brand:, created_at: start_time.utc..now).count
      end

      def active_count(start_time)
        Session.where(brand:, last_used_at: start_time.utc..now).distinct.count(:user_id)
      end

      def gender_split
        counts = Profile.kept.where(brand:).group(:gender).count
        unknown = counts[nil].to_i + counts[""].to_i
        known = counts.except(nil, "", "woman", "man")

        {
          woman: counts["woman"].to_i,
          man: counts["man"].to_i,
          other: known.values.sum,
          unknown:
        }
      end
    end
  end
end
