module Hq
  module Metrics
    # Typed HQ metric payload. Status distinguishes a real zero from missing data.
    MetricValue = Data.define(
      :metric_id, :version, :definition, :status, :value, :unit, :limitations, :numerator, :denominator
    ) do
      def self.available(metric_id:, definition:, value:, unit: "count", version: 1, limitations: [], numerator: nil, denominator: nil)
        new(
          metric_id:, version:, definition:, status: "available", value:, unit:,
          limitations:, numerator:, denominator:
        )
      end

      def self.unavailable(metric_id:, definition:, limitations:, version: 1)
        new(
          metric_id:, version:, definition:, status: "unavailable", value: nil, unit: nil,
          limitations:, numerator: nil, denominator: nil
        )
      end

      def self.insufficient_data(metric_id:, definition:, limitations:, version: 1)
        new(
          metric_id:, version:, definition:, status: "insufficient_data", value: nil, unit: nil,
          limitations:, numerator: nil, denominator: nil
        )
      end

      def to_h
        payload = {
          metric_id:,
          version:,
          definition:,
          status:,
          unit:,
          limitations:
        }
        payload[:value] = value unless value.nil?
        payload[:numerator] = numerator unless numerator.nil?
        payload[:denominator] = denominator unless denominator.nil?
        payload
      end
    end
  end
end
