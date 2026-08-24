module Matching
  module Strategies
    class Date9jaContract
      KEY = "date9ja_contract_v1"

      def self.key
        KEY
      end

      def self.production_ready?
        false
      end

      def self.rank(scope:, viewer:, eligibility_policy:)
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
