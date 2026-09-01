module Hq
  module ProductIntelligence
    class Trends
      Result = Data.define(:brand, :window, :generated_at, :time_zone, :series)

      def self.call(brand:, window:, now: Time.current)
        new(brand:, window:, now:).call
      end

      def initialize(brand:, window:, now:)
        @brand = brand
        @window_key = window.to_s
        @window = Window.resolve(key: @window_key, now:)
        @now = now
      end

      def call
        Result.new(
          brand: brand.slug,
          window: window_key,
          generated_at: now,
          time_zone: Hq::Metrics::Windows::TIME_ZONE,
          series: [
            series("registrations", "Kept brand memberships created on each brand-local calendar date.", BrandMembership.kept.where(brand:, created_at: range), time_column: "created_at"),
            series("profile_publications", "Profile publication events recorded on each brand-local calendar date.", AnalyticsEvent.where(brand:, event_type: "profile.published", occurred_at: range), time_column: "occurred_at", distinct: :user_id, limitations: [ "Only instrumented publications are counted." ]),
            series("likes", "Kept Like rows created on each brand-local calendar date.", Like.kept.where(brand:, created_at: range), time_column: "created_at"),
            series("matches", "Kept Match rows created on each brand-local calendar date.", Match.kept.where(brand:, created_at: range), time_column: "created_at"),
            series("conversations", "Kept Conversation rows created on each brand-local calendar date.", Conversation.kept.where(brand:, created_at: range), time_column: "created_at")
          ]
        )
      end

      private

      attr_reader :brand, :window_key, :window, :now

      def range
        window.start_at.utc...window.end_at.utc
      end

      def series(id, definition, relation, time_column:, distinct: nil, limitations: [])
        grouped = relation.group(local_date_expression(relation, time_column))
        grouped = grouped.distinct if distinct
        counts = distinct ? grouped.count(distinct) : grouped.count

        {
          id:, definition:, status: "available", unit: "count", limitations:,
          points: dates.index_with { |date| counts.fetch(date, 0) }
        }
      end

      def local_date_expression(relation, time_column)
        column = relation.klass.arel_table[time_column]
        local_timestamp = Arel::Nodes::InfixOperation.new(
          "AT TIME ZONE", column, Arel::Nodes.build_quoted(Hq::Metrics::Windows::TIME_ZONE)
        )
        Arel::Nodes::NamedFunction.new("DATE", [ local_timestamp ])
      end

      def dates
        local_start = window.start_at.in_time_zone(Hq::Metrics::Windows::TIME_ZONE)
        local_end = window.end_at.in_time_zone(Hq::Metrics::Windows::TIME_ZONE)
        end_date = local_end.to_date
        end_date += 1.day if local_end > local_end.beginning_of_day
        (local_start.to_date...end_date).to_a
      end
    end
  end
end
