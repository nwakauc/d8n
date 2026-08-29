module Hq
  # Bounded, newest-first AuthAttempt history for one member, brand-scoped.
  # Closes CURRENT-STATE.md #1.4: AuthAttempt is written correctly today but
  # has no admin read API at all.
  class AuthAttemptHistory
    DEFAULT_LIMIT = 25
    MAX_LIMIT = 100
    PURPOSE = "hq-auth-attempts-cursor"

    Result = Data.define(:attempts, :next_cursor)

    def self.call(brand:, user:, cursor: nil, limit: nil)
      new(brand:, user:, cursor:, limit:).call
    end

    def initialize(brand:, user:, cursor:, limit:)
      @brand = brand
      @user = user
      @cursor = cursor
      @limit = normalize_limit(limit)
    end

    def call
      scope = AuthAttempt.where(brand:, user:).order(created_at: :desc, id: :desc)
      scope = Cursor.apply(scope:, purpose: PURPOSE, value: cursor, brand:, user:, table: "auth_attempts")
      rows = scope.limit(limit + 1).to_a
      has_more = rows.length > limit
      rows = rows.first(limit)

      Result.new(
        attempts: rows,
        next_cursor: has_more ? Cursor.encode(purpose: PURPOSE, brand:, user:, record: rows.last) : nil
      )
    end

    private

    attr_reader :brand, :user, :cursor, :limit

    def normalize_limit(value)
      return DEFAULT_LIMIT if value.blank?

      parsed = Integer(value, 10)
      raise HqError, :invalid_limit unless parsed.between?(1, MAX_LIMIT)

      parsed
    rescue ArgumentError, TypeError
      raise HqError, :invalid_limit
    end
  end
end
