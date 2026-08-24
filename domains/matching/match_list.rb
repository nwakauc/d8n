module Matching
  class MatchList
    DEFAULT_LIMIT = 20
    MAX_LIMIT = 50

    class InvalidLimit < StandardError; end

    Result = Data.define(:matches, :viewer, :next_cursor)

    def self.call(user:, brand:, cursor: nil, limit: nil)
      new(user:, brand:, cursor:, limit:).call
    end

    def initialize(user:, brand:, cursor:, limit:)
      @user = user
      @brand = brand
      @cursor = cursor
      @limit = normalize_limit(limit)
    end

    def call
      viewer = ProfileParticipant.match_member!(user:, brand:)
      scope = Match.kept.status_active.where(brand:)
        .where("profile_a_id = :id OR profile_b_id = :id", id: viewer.id)
        .joins(participant_availability_joins)
        .where(match_profile_as: { deleted_at: nil }, match_profile_bs: { deleted_at: nil })
        .where.not(match_profile_as: { status: Profile.statuses.fetch("suspended") })
        .where.not(match_profile_bs: { status: Profile.statuses.fetch("suspended") })
        .where(
          match_user_as: { deleted_at: nil, status: User.statuses.fetch("active") },
          match_user_bs: { deleted_at: nil, status: User.statuses.fetch("active") },
          match_membership_as: { deleted_at: nil, status: BrandMembership.statuses.fetch("active") },
          match_membership_bs: { deleted_at: nil, status: BrandMembership.statuses.fetch("active") }
        )
      scope = Trust::BlockPolicy.exclude_matches(scope:)
        .order(created_at: :desc, public_id: :desc)
      scope = MatchCursor.apply(scope:, value: cursor, brand:, viewer:)
      matches = scope.includes(
        profile_a: [ :brand, { profile_option_selections: [ :profile_option, :profile_option_group ] },
                     { profile_photos: { display_image_attachment: :blob } } ],
        profile_b: [ :brand, { profile_option_selections: [ :profile_option, :profile_option_group ] },
                     { profile_photos: { display_image_attachment: :blob } } ]
      ).limit(limit + 1).to_a
      has_more = matches.length > limit
      matches = matches.first(limit)

      Result.new(
        matches:,
        viewer:,
        next_cursor: has_more ? MatchCursor.encode(brand:, viewer:, match: matches.last) : nil
      )
    end

    private

    attr_reader :user, :brand, :cursor, :limit

    def participant_availability_joins
      <<~SQL.squish
        INNER JOIN profiles match_profile_as
          ON match_profile_as.id = matches.profile_a_id AND match_profile_as.brand_id = matches.brand_id
        INNER JOIN users match_user_as ON match_user_as.id = match_profile_as.user_id
        INNER JOIN brand_memberships match_membership_as
          ON match_membership_as.id = match_profile_as.brand_membership_id
        INNER JOIN profiles match_profile_bs
          ON match_profile_bs.id = matches.profile_b_id AND match_profile_bs.brand_id = matches.brand_id
        INNER JOIN users match_user_bs ON match_user_bs.id = match_profile_bs.user_id
        INNER JOIN brand_memberships match_membership_bs
          ON match_membership_bs.id = match_profile_bs.brand_membership_id
      SQL
    end

    def normalize_limit(value)
      return DEFAULT_LIMIT if value.blank?

      parsed = Integer(value, 10)
      raise InvalidLimit, "limit must be between 1 and #{MAX_LIMIT}" unless parsed.between?(1, MAX_LIMIT)

      parsed
    rescue ArgumentError, TypeError
      raise InvalidLimit, "limit must be between 1 and #{MAX_LIMIT}"
    end
  end
end
