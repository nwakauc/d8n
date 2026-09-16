module Accounts
  # Bounded, newest-first SecurityEvent history for a member's OWN self-view
  # (Settings → Account). Distinct from Hq::SecurityEventHistory (admin-facing,
  # unrestricted event types): this is deliberately scoped to an allowlist of
  # member-relevant, self-explanatory event types (auth./account.) and never
  # exposes `metadata`, since that field is written ad hoc across many call
  # sites (including moderation/trust domains) and has not been individually
  # audited as safe for a member's own eyes.
  class MemberSecurityEvents
    DEFAULT_LIMIT = 20
    MAX_LIMIT = 50

    VISIBLE_EVENT_TYPE_PREFIXES = %w[auth. account.].freeze

    def self.call(brand:, user:, limit: nil)
      new(brand:, user:, limit:).call
    end

    def initialize(brand:, user:, limit:)
      @brand = brand
      @user = user
      @limit = normalize_limit(limit)
    end

    def call
      pattern = VISIBLE_EVENT_TYPE_PREFIXES.map { |prefix| "event_type LIKE ?" }.join(" OR ")
      binds = VISIBLE_EVENT_TYPE_PREFIXES.map { |prefix| "#{prefix}%" }
      SecurityEvent.where(brand:, user:).where(pattern, *binds).order(created_at: :desc).limit(limit)
    end

    private

    attr_reader :brand, :user, :limit

    def normalize_limit(value)
      return DEFAULT_LIMIT if value.blank?

      parsed = Integer(value, 10)
      parsed.clamp(1, MAX_LIMIT)
    rescue ArgumentError, TypeError
      DEFAULT_LIMIT
    end
  end
end
