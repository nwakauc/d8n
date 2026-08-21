module Matching
  module Strategies
    # Non-production contract proof only. DateZA is intentionally absent from the
    # production discovery registry until stable daily Discovery batches are
    # implemented. DateZA Find and DateZA v1 pair compatibility are separate
    # production capabilities with their own policy/strategy boundaries.
    class DatezaContract
      KEY = "dateza_contract_v1"
      LOCATION_MAX_AGE = 24.hours

      def self.key
        KEY
      end

      def self.location_max_age
        LOCATION_MAX_AGE
      end

      def self.production_ready?
        false
      end

      def self.rank(scope:, viewer:)
        scope.select(
          "profiles.*",
          "0 AS matching_score",
          "0.0 AS matching_confidence"
        ).order("profiles.created_at DESC", "profiles.public_id DESC")
      end

      def self.cursor_payload(profile:)
        {}
      end

      def self.apply_cursor(scope:, payload:)
        created_at = Time.iso8601(payload.fetch(:created_at))
        public_id = payload.fetch(:profile).to_s
        raise Cursor::Invalid, "cursor is invalid" unless public_id.match?(Profile::PUBLIC_ID_FORMAT)

        scope.where(
          "profiles.created_at < ? OR (profiles.created_at = ? AND profiles.public_id < ?)",
          created_at, created_at, public_id
        )
      rescue ArgumentError, KeyError, TypeError
        raise Cursor::Invalid, "cursor is invalid"
      end

      def self.compatibility(profile:)
        {
          score: Integer(profile[:matching_score]),
          confidence: profile[:matching_confidence].to_f,
          reasons: []
        }
      end
    end
  end
end
