module Matching
  # Reusable D8N read surface: profiles the viewer has liked that remain a
  # current, actionable pre-match relationship state — not blocked (either
  # direction), not yet a Match (a mutual Like belongs on Matching::MatchList,
  # not here), and otherwise visible under Matching::VisibilityScope. Mirrors
  # Matching::IncomingLikes with liker/liked swapped; see that class for the
  # shared reasoning.
  class OutgoingLikes
    DEFAULT_LIMIT = 20
    MAX_LIMIT = 50
    DIRECTION = "outgoing"

    class InvalidLimit < StandardError; end

    Result = Data.define(:likes, :viewer, :next_cursor)

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
      scope = Like.kept.kind_like.where(brand:, liker_profile: viewer)
        .where(liked_profile_id: VisibilityScope.call(brand:, viewer:).select(:id))
        .where.not(liked_profile_id: matched_profile_ids(viewer))
        .joins(:liked_profile)
        .order("likes.created_at DESC, profiles.public_id DESC")
      scope = LikesCursor.apply(scope:, value: cursor, brand:, viewer:, direction: DIRECTION)
      likes = scope.includes(
        liked_profile: [
          :brand,
          { profile_option_selections: [ :profile_option, :profile_option_group ] },
          { profile_photos: { display_image_attachment: :blob } }
        ]
      ).limit(limit + 1).to_a
      has_more = likes.length > limit
      likes = likes.first(limit)

      Result.new(
        likes:,
        viewer:,
        next_cursor: has_more ? encode_cursor(viewer:, like: likes.last) : nil
      )
    end

    private

    attr_reader :user, :brand, :cursor, :limit

    def encode_cursor(viewer:, like:)
      LikesCursor.encode(
        brand:, viewer:, direction: DIRECTION, created_at: like.created_at, counterpart: like.liked_profile
      )
    end

    def matched_profile_ids(viewer)
      Match.kept.status_active.where(brand:)
        .where("profile_a_id = :id OR profile_b_id = :id", id: viewer.id)
        .pluck(:profile_a_id, :profile_b_id)
        .flatten.uniq - [ viewer.id ]
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
