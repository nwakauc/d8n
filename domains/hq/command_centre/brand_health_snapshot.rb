module Hq
  module CommandCentre
    class BrandHealthSnapshot
      Result = Data.define(:brand_health)

      def self.call(brand:, now: Time.current)
        new(brand:, now:).call
      end

      def initialize(brand:, now:)
        @brand = brand
        @now = now
      end

      def call
        metrics = ::Hq::Metrics::Compute.call(brand:, now:)
        signals = AttentionSignals.call(
          brand:,
          inputs: attention_inputs(metrics),
          as_of: now
        )

        Result.new(brand_health: metrics.merge(attention_signals: signals))
      end

      private

      attr_reader :brand, :now

      def attention_inputs(metrics)
        trust = metrics.fetch(:trust_safety)
        marketplace = metrics.fetch(:marketplace)
        {
          oldest_open_report_age_seconds: trust.dig(:oldest_open_report_age_seconds, :value),
          awaiting_decision: trust.dig(:awaiting_decision, :value),
          active_enforcements: trust.dig(:active_enforcements, :value),
          pending_photo_reviews: trust.dig(:pending_photo_reviews, :value),
          zero_discovery_yesterday: marketplace.dig(:zero_discovery_allocations, :yesterday, :value),
          unavailable_metric_ids: unavailable_metric_ids(metrics)
        }
      end

      def unavailable_metric_ids(value, path = [])
        case value
        when Hash
          value.flat_map { |key, child| unavailable_metric_ids(child, path + [ key ]) }
        when Array
          value.flat_map { |child| unavailable_metric_ids(child, path) }
        else
          return [] unless path.last == :status && value == "unavailable"

          [ path[-2] ]
        end
      end
    end
  end
end
