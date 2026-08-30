module Hq
  # Bounded, newest-first directory of members belonging to one brand. This
  # intentionally returns a safe operational summary, not contact identifiers
  # or a second Member 360 payload.
  class MemberDirectory
    DEFAULT_LIMIT = 25
    MAX_LIMIT = 100
    STATUSES = BrandMembership.statuses.keys.freeze

    Result = Data.define(:members, :next_cursor)

    def self.call(brand:, cursor: nil, limit: nil, status: nil)
      new(brand:, cursor:, limit:, status:).call
    end

    def initialize(brand:, cursor:, limit:, status:)
      @brand = brand
      @cursor = cursor
      @limit = normalize_limit(limit)
      @status = normalize_status(status)
    end

    def call
      scope = BrandMembership.kept.where(brand:).order(created_at: :desc, id: :desc)
      scope = scope.where(status: status) if status.present?
      scope = MemberDirectoryCursor.apply(scope:, value: cursor, brand:, status: status)
      memberships = scope.includes(:user, :profile).limit(limit + 1).to_a
      has_more = memberships.length > limit
      memberships = memberships.first(limit)

      Result.new(
        members: memberships,
        next_cursor: has_more ? MemberDirectoryCursor.encode(brand:, status:, membership: memberships.last) : nil
      )
    end

    private

    attr_reader :brand, :cursor, :limit, :status

    def normalize_status(value)
      return nil if value.blank?
      raise HqError, :invalid_filter unless STATUSES.include?(value.to_s)

      value.to_s
    end

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
