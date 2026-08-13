module Matching
  module Strategies
    class Hookus
      KEY = "hookus_v1"
      LOCATION_MAX_AGE = 24.hours

      def self.key
        KEY
      end

      def self.location_max_age
        LOCATION_MAX_AGE
      end

      def self.rank(scope:, viewer:)
        scope.order(created_at: :desc, public_id: :desc)
      end
    end
  end
end
