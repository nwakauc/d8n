module Hq
  module TrustSafety
    # Bounded repeat-offender aggregation for one brand. "Repeat" means at
    # least two retained reports received by the same profile; it is an
    # investigation signal, never an automatic enforcement decision.
    class RepeatOffenders
      DEFAULT_LIMIT = 25
      MAX_LIMIT = 100
      MINIMUM_REPORTS = 2

      Offender = Data.define(
        :profile_id, :display_name, :member_360_lookup, :report_count,
        :awaiting_decision_count, :latest_report_at
      )
      Result = Data.define(:offenders, :minimum_reports, :truncated)

      def self.call(brand:, limit: nil)
        new(brand:, limit:).call
      end

      def initialize(brand:, limit:)
        @brand = brand
        @limit = normalize_limit(limit)
      end

      def call
        aggregates = aggregate_scope.limit(limit + 1).to_a
        truncated = aggregates.length > limit
        aggregates = aggregates.first(limit)
        profile_ids = aggregates.map(&:reported_profile_id)
        profiles = Profile.where(id: profile_ids).index_by(&:id)
        awaiting_counts = Report.where(
          brand:, reported_profile_id: profile_ids, status: %i[open reviewing]
        ).group(:reported_profile_id).count

        Result.new(
          offenders: aggregates.filter_map do |aggregate|
            serialize(
              aggregate,
              profiles[aggregate.reported_profile_id],
              awaiting_counts.fetch(aggregate.reported_profile_id, 0)
            )
          end,
          minimum_reports: MINIMUM_REPORTS,
          truncated:
        )
      end

      private

      attr_reader :brand, :limit

      def aggregate_scope
        Report.where(brand:)
          .select(
            :reported_profile_id,
            "COUNT(*) AS report_count",
            "MAX(created_at) AS latest_report_at"
          )
          .group(:reported_profile_id)
          .having("COUNT(*) >= ?", MINIMUM_REPORTS)
          .order(Arel.sql("COUNT(*) DESC, MAX(created_at) DESC, reported_profile_id ASC"))
      end

      def serialize(aggregate, profile, awaiting_decision_count)
        return if profile.blank?

        Offender.new(
          profile_id: profile.public_id,
          display_name: profile.display_name,
          member_360_lookup: profile.deleted_at.nil? ? profile.public_id : nil,
          report_count: aggregate.read_attribute(:report_count).to_i,
          awaiting_decision_count:,
          latest_report_at: aggregate.read_attribute(:latest_report_at)
        )
      end

      def normalize_limit(value)
        return DEFAULT_LIMIT if value.blank?

        parsed = Integer(value.to_s, 10)
        raise HqError, :invalid_limit unless parsed.between?(1, MAX_LIMIT)

        parsed
      rescue ArgumentError, TypeError
        raise HqError, :invalid_limit
      end
    end
  end
end
