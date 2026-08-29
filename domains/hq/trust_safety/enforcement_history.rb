module Hq
  module TrustSafety
    # Bounded, newest-first enforcement history across one brand. This is the
    # brand-wide Phase 2 counterpart to Phase 1's per-member history.
    class EnforcementHistory
      DEFAULT_LIMIT = 25
      MAX_LIMIT = 100
      STATES = %w[active reverted].freeze

      Result = Data.define(:enforcements, :next_cursor)

      def self.call(brand:, state: nil, cursor: nil, limit: nil)
        new(brand:, state:, cursor:, limit:).call
      end

      def initialize(brand:, state:, cursor:, limit:)
        @brand = brand
        @state = normalize_state(state)
        @cursor = cursor
        @limit = normalize_limit(limit)
      end

      def call
        scope = AccountEnforcement.where(brand:).order(created_at: :desc, id: :desc)
        scope = apply_state(scope)
        scope = EnforcementCursor.apply(scope:, value: cursor, brand:, state:)
        rows = scope.includes(:profile).limit(limit + 1).to_a
        has_more = rows.length > limit
        rows = rows.first(limit)

        Result.new(
          enforcements: rows,
          next_cursor: has_more ? EnforcementCursor.encode(brand:, state:, enforcement: rows.last) : nil
        )
      end

      private

      attr_reader :brand, :state, :cursor, :limit

      def apply_state(scope)
        return scope if state.blank?
        return scope.where(reverted_at: nil) if state == "active"

        scope.where.not(reverted_at: nil)
      end

      def normalize_state(value)
        return if value.blank?
        raise HqError, :invalid_filter unless STATES.include?(value.to_s)

        value.to_s
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
