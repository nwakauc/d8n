module Hq
  module ProductIntelligence
    class Window
      KEYS = %w[today yesterday last_7d previous_7d last_30d previous_30d].freeze

      def self.resolve(key:, now: Time.current)
        windows = Hq::Metrics::Windows.build(now:)
        raise ArgumentError, "unsupported window" unless KEYS.include?(key.to_s)

        windows.fetch(key.to_sym)
      end
    end
  end
end
