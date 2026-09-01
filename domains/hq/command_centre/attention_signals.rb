module Hq
  module CommandCentre
    # Deterministic operational attention signals for Founder HQ. No scoring model,
    # no AI — each signal explains itself with a fixed threshold.
    class AttentionSignals
      OLD_REPORT_THRESHOLD_SECONDS = 72.hours.to_i

      Signal = Data.define(:signal, :severity, :title, :reason, :value, :unit) do
        def to_h
          { signal:, severity:, title:, reason:, value:, unit: }
        end
      end

      def self.call(brand:, inputs:, as_of: Time.current)
        new(brand:, inputs:, as_of:).call
      end

      def initialize(brand:, inputs:, as_of:)
        @brand = brand
        @inputs = inputs
        @as_of = as_of
      end

      def call
        [
          old_unresolved_report,
          pending_photo_backlog,
          active_enforcement_present,
          zero_discovery_yesterday,
          unavailable_metrics
        ].compact.map(&:to_h)
      end

      private

      attr_reader :brand, :inputs

      def old_unresolved_report
        age = inputs[:oldest_open_report_age_seconds]
        return if age.nil? || age < OLD_REPORT_THRESHOLD_SECONDS

        Signal.new(
          signal: "old_unresolved_report",
          severity: "warning",
          title: "Oldest open report is aging",
          reason: "Open reports older than #{OLD_REPORT_THRESHOLD_SECONDS / 1.hour} hours need operator review. SLA policy is not configured; this uses a fixed operational threshold.",
          value: age,
          unit: "seconds"
        )
      end

      def pending_photo_backlog
        count = inputs[:pending_photo_reviews].to_i
        return if count <= 0

        Signal.new(
          signal: "pending_photo_reviews",
          severity: "warning",
          title: "Photo moderation backlog",
          reason: "#{count} profile photo(s) are awaiting review on #{brand.slug}.",
          value: count,
          unit: "count"
        )
      end

      def active_enforcement_present
        count = inputs[:active_enforcements].to_i
        return if count <= 0

        Signal.new(
          signal: "active_enforcements",
          severity: "info",
          title: "Active enforcements on brand",
          reason: "#{count} active suspension or ban enforcement(s) on #{brand.slug}.",
          value: count,
          unit: "count"
        )
      end

      def zero_discovery_yesterday
        count = inputs[:zero_discovery_yesterday]
        return if count.nil? || count.to_i <= 0

        Signal.new(
          signal: "zero_discovery_allocations",
          severity: "warning",
          title: "Members received empty discovery",
          reason: "#{count} discovery allocation(s) yesterday returned zero candidates on #{brand.slug}.",
          value: count.to_i,
          unit: "count"
        )
      end

      def unavailable_metrics
        metric_ids = inputs[:unavailable_metric_ids].to_a
        return if metric_ids.empty?

        Signal.new(
          signal: "metric_unavailable",
          severity: "info",
          title: "Some Command Centre metrics are unavailable",
          reason: "The following metrics are not computed from the current data sources: #{metric_ids.join(', ')}.",
          value: metric_ids.size,
          unit: "metrics"
        )
      end
    end
  end
end
