module Hq
  module TrustSafety
    # Cheap, brand-scoped snapshot for the Trust & Safety command surface.
    # A true overdue/SLA count is deliberately unavailable until D8N defines an
    # SLA policy; returning nil keeps HQ from manufacturing a threshold.
    class Overview
      Result = Data.define(
        :brand, :generated_at, :report_count, :counts_by_status,
        :awaiting_decision_count, :oldest_open_report_at,
        :oldest_open_report_age_seconds, :counts_by_reason,
        :counts_by_target_type, :sla_status, :overdue_count,
        :enforcement_count, :active_enforcement_count
      )

      def self.call(brand:, as_of: Time.current)
        new(brand:, as_of:).call
      end

      def initialize(brand:, as_of:)
        @brand = brand
        @as_of = as_of
      end

      def call
        reports = Report.where(brand:)
        oldest_open_report_at = reports.status_open.minimum(:created_at)

        Result.new(
          brand: brand.slug,
          generated_at: as_of,
          report_count: reports.count,
          counts_by_status: complete_counts(reports.group(:status).count, Report.statuses),
          awaiting_decision_count: reports.where(status: %i[open reviewing]).count,
          oldest_open_report_at:,
          oldest_open_report_age_seconds: age_seconds(oldest_open_report_at),
          counts_by_reason: complete_counts(reports.group(:reason).count, Report.reasons),
          counts_by_target_type: complete_counts(reports.group(:target_type).count, Report.target_types),
          sla_status: "not_configured",
          overdue_count: nil,
          enforcement_count: AccountEnforcement.where(brand:).count,
          active_enforcement_count: AccountEnforcement.active.where(brand:).count
        )
      end

      private

      attr_reader :brand, :as_of

      def complete_counts(counts, enum_values)
        enum_values.keys.index_with { |key| counts.fetch(key, 0) }
      end

      def age_seconds(timestamp)
        return if timestamp.blank?

        [ (as_of - timestamp).to_i, 0 ].max
      end
    end
  end
end
