module Admin
  # Bounded, oldest-first moderation queue for one brand. Optionally filters by
  # status. Reporter and reported profiles are preloaded so serialization issues no
  # per-row queries. Reports are never soft-deleted, so historical records for
  # since-removed profiles remain visible for moderation.
  class ReportQueue
    DEFAULT_LIMIT = 25
    MAX_LIMIT = 100

    Result = Data.define(:reports, :next_cursor)

    def self.call(brand:, status: nil, cursor: nil, limit: nil)
      new(brand:, status:, cursor:, limit:).call
    end

    def initialize(brand:, status:, cursor:, limit:)
      @brand = brand
      @status = normalize_status(status)
      @cursor = cursor
      @limit = normalize_limit(limit)
    end

    def call
      scope = Report.where(brand:).order("reports.created_at ASC", "reports.id ASC")
      scope = scope.where(status: @status) if @status
      scope = ReportCursor.apply(scope:, value: cursor, brand:)
      reports = scope.includes(:reporter_profile, :reported_profile, :reviewed_by).limit(limit + 1).to_a
      has_more = reports.length > limit
      reports = reports.first(limit)

      Result.new(reports:, next_cursor: has_more ? ReportCursor.encode(brand:, report: reports.last) : nil)
    end

    private

    attr_reader :brand, :cursor, :limit

    def normalize_status(value)
      return if value.blank?
      raise ModerationError, :invalid_filter unless Report.statuses.key?(value.to_s)

      value.to_s
    end

    def normalize_limit(value)
      return DEFAULT_LIMIT if value.blank?

      parsed = Integer(value, 10)
      raise ModerationError, :invalid_limit unless parsed.between?(1, MAX_LIMIT)

      parsed
    rescue ArgumentError, TypeError
      raise ModerationError, :invalid_limit
    end
  end
end
