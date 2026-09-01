module Hq
  # Bounded, newest-first directory of members belonging to one brand. This
  # intentionally returns a safe operational summary, not contact identifiers
  # or a second Member 360 payload.
  class MemberDirectory
    DEFAULT_LIMIT = 25
    MAX_LIMIT = 100
    STATUSES = BrandMembership.statuses.keys.freeze
    PROFILE_STATUSES = Profile.statuses.keys.freeze
    VISIBILITIES = Profile.visibilities.keys.freeze
    CONTACT_VERIFICATION_STATES = %w[any verified unverified].freeze
    ENFORCEMENT_STATES = %w[any active none].freeze
    SORTS = %w[newest oldest recently_active].freeze
    MAX_SEARCH_LENGTH = 100
    LAST_ACTIVE_SQL = "(SELECT MAX(sessions.last_used_at) FROM sessions " \
      "WHERE sessions.user_id = brand_memberships.user_id " \
      "AND sessions.brand_id = brand_memberships.brand_id)".freeze

    Result = Data.define(:members, :next_cursor)

    def self.call(brand:, cursor: nil, limit: nil, search: nil, status: nil,
      profile_status: nil, visibility: nil, contact_verification: nil,
      enforcement: nil, created_from: nil, created_to: nil,
      last_active_from: nil, last_active_to: nil, sort: nil)
      new(
        brand:, cursor:, limit:, search:, status:, profile_status:, visibility:,
        contact_verification:, enforcement:, created_from:, created_to:,
        last_active_from:, last_active_to:, sort:
      ).call
    end

    def initialize(brand:, cursor:, limit:, search:, status:, profile_status:, visibility:,
      contact_verification:, enforcement:, created_from:, created_to:,
      last_active_from:, last_active_to:, sort:)
      @brand = brand
      @cursor = cursor
      @limit = normalize_limit(limit)
      @search = normalize_search(search)
      @status = normalize_enum(status, STATUSES)
      @profile_status = normalize_enum(profile_status, PROFILE_STATUSES)
      @visibility = normalize_enum(visibility, VISIBILITIES)
      @contact_verification = normalize_enum(contact_verification, CONTACT_VERIFICATION_STATES, default: "any")
      @enforcement = normalize_enum(enforcement, ENFORCEMENT_STATES, default: "any")
      @created_from = normalize_time(created_from)
      @created_to = normalize_time(created_to)
      @last_active_from = normalize_time(last_active_from)
      @last_active_to = normalize_time(last_active_to)
      @sort = normalize_enum(sort, SORTS, default: "newest")
      validate_ranges!
    end

    def call
      scope = BrandMembership.kept.where(brand:)
      scope = apply_search(scope)
      scope = scope.where(status: status) if status.present?
      scope = scope.joins(:profile) if profile_filters?
      scope = scope.where(profiles: { status: profile_status }) if profile_status.present?
      scope = scope.where(profiles: { visibility: visibility }) if visibility.present?
      scope = apply_contact_verification(scope)
      scope = apply_enforcement(scope)
      scope = scope.where(created_at: created_from..) if created_from
      scope = scope.where(created_at: ..created_to) if created_to
      scope = apply_last_active_filter(scope)
      scope = scope.select("brand_memberships.*", "#{last_active_sql} AS last_active_at")
      scope = apply_sort(scope)
      scope = MemberDirectoryCursor.apply(scope:, value: cursor, brand:, query: cursor_query, sort:)
      memberships = scope.includes(:user, :profile).limit(limit + 1).to_a
      has_more = memberships.length > limit
      memberships = memberships.first(limit)

      Result.new(
        members: memberships,
        next_cursor: has_more ? MemberDirectoryCursor.encode(
          brand:, query: cursor_query, sort:, membership: memberships.last
        ) : nil
      )
    end

    private

    attr_reader :brand, :cursor, :limit, :search, :status, :profile_status,
      :visibility, :contact_verification, :enforcement, :created_from, :created_to,
      :last_active_from, :last_active_to, :sort

    def normalize_search(value)
      normalized = value.to_s.strip.presence
      return if normalized.blank?
      raise HqError, :invalid_search if normalized.length > MAX_SEARCH_LENGTH

      normalized
    end

    def normalize_limit(value)
      return DEFAULT_LIMIT if value.blank?

      parsed = Integer(value, 10)
      raise HqError, :invalid_limit unless parsed.between?(1, MAX_LIMIT)

      parsed
    rescue ArgumentError, TypeError
      raise HqError, :invalid_limit
    end

    def normalize_enum(value, allowed, default: nil)
      return default if value.blank?
      raise HqError, :invalid_filter unless allowed.include?(value.to_s)

      value.to_s
    end

    def normalize_time(value)
      return if value.blank?

      Time.iso8601(value.to_s)
    rescue ArgumentError, TypeError
      raise HqError, :invalid_filter
    end

    def validate_ranges!
      raise HqError, :invalid_filter if created_from && created_to && created_from > created_to
      raise HqError, :invalid_filter if last_active_from && last_active_to && last_active_from > last_active_to
    end

    def profile_filters?
      profile_status.present? || visibility.present?
    end

    def apply_search(scope)
      return scope if search.blank?

      if search.match?(Profile::PUBLIC_ID_FORMAT)
        return scope.where(user_id: Profile.kept.where(brand:, public_id: search).select(:user_id))
      end

      identifier = ::Identity::LoginIdentifier.call(search, brand:)
      if identifier.present?
        return scope.where(
          user_id: IdentityIdentifier.kept.where(
            kind: identifier.kind, normalized_value: identifier.lookup_values
          ).select(:user_id)
        )
      end

      pattern = "#{ActiveRecord::Base.sanitize_sql_like(search)}%"
      matching_profiles = Profile.kept.where(brand:).where("LOWER(display_name) LIKE LOWER(?)", pattern).select(:user_id)
      matching_users = User.kept.where(
        "LOWER(first_name) LIKE LOWER(:pattern) OR LOWER(last_name) LIKE LOWER(:pattern)", pattern:
      ).select(:id)
      scope.where(user_id: matching_profiles).or(scope.where(user_id: matching_users))
    end

    def apply_contact_verification(scope)
      return scope if contact_verification == "any"

      verified = ::IdentityIdentifier.kept.contact.where.not(verified_at: nil)
        .where(user_id: scope.select(:user_id)).select(:user_id)
      return scope.where(user_id: verified) if contact_verification == "verified"

      scope.where.not(user_id: verified)
    end

    def apply_enforcement(scope)
      return scope if enforcement == "any"

      active = AccountEnforcement.active.where(brand:).select(:brand_membership_id)
      return scope.where(id: active) if enforcement == "active"

      scope.where.not(id: active)
    end

    def last_active_sql
      LAST_ACTIVE_SQL
    end

    def apply_last_active_filter(scope)
      scope = scope.where(LAST_ACTIVE_SQL + " >= ?", last_active_from) if last_active_from
      scope = scope.where(LAST_ACTIVE_SQL + " <= ?", last_active_to) if last_active_to
      scope
    end

    def apply_sort(scope)
      case sort
      when "oldest"
        scope.order(created_at: :asc, id: :asc)
      when "recently_active"
        scope.order(Arel.sql(LAST_ACTIVE_SQL + " DESC NULLS LAST"), created_at: :desc, id: :desc)
      else
        scope.order(created_at: :desc, id: :desc)
      end
    end

    def cursor_query
      {
        search:, status:, profile_status:, visibility:, contact_verification:, enforcement:,
        created_from: created_from&.iso8601, created_to: created_to&.iso8601,
        last_active_from: last_active_from&.iso8601, last_active_to: last_active_to&.iso8601,
        sort:
      }
    end
  end
end
