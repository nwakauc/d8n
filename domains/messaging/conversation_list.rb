module Messaging
  class ConversationList
    DEFAULT_LIMIT = 20
    MAX_LIMIT = 50

    class InvalidLimit < StandardError; end

    Result = Data.define(:conversations, :viewer, :next_cursor)

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
      viewer = Matching::ProfileParticipant.match_member!(user:, brand:)
      scope = Conversation.kept.status_active.where(brand:)
        .joins(:conversation_participants, :match)
        .where(conversation_participants: { profile_id: viewer.id, deleted_at: nil })
        .where(matches: { deleted_at: nil })
        .joins(participant_availability_joins)
        .where(message_profile_as: { deleted_at: nil }, message_profile_bs: { deleted_at: nil })
        .where.not(message_profile_as: { status: Profile.statuses.fetch("suspended") })
        .where.not(message_profile_bs: { status: Profile.statuses.fetch("suspended") })
        .where(
          message_user_as: { deleted_at: nil, status: User.statuses.fetch("active") },
          message_user_bs: { deleted_at: nil, status: User.statuses.fetch("active") },
          message_membership_as: { deleted_at: nil, status: BrandMembership.statuses.fetch("active") },
          message_membership_bs: { deleted_at: nil, status: BrandMembership.statuses.fetch("active") }
        )
      scope = Trust::BlockPolicy.exclude_matches(scope:)
        .order("conversations.created_at DESC", "conversations.public_id DESC")
      scope = ConversationCursor.apply(scope:, value: cursor, brand:, viewer:)
      conversations = scope.preload(
        :match,
        conversation_participants: { profile: { profile_option_selections: [ :profile_option, :profile_option_group ] } }
      ).limit(limit + 1).to_a
      has_more = conversations.length > limit
      conversations = conversations.first(limit)

      Result.new(
        conversations:,
        viewer:,
        next_cursor: has_more ? ConversationCursor.encode(brand:, viewer:, conversation: conversations.last) : nil
      )
    rescue Matching::InteractionError
      raise AccessError, :conversation_unavailable
    end

    private

    attr_reader :user, :brand, :cursor, :limit

    def participant_availability_joins
      <<~SQL.squish
        INNER JOIN profiles message_profile_as
          ON message_profile_as.id = matches.profile_a_id AND message_profile_as.brand_id = conversations.brand_id
        INNER JOIN users message_user_as ON message_user_as.id = message_profile_as.user_id
        INNER JOIN brand_memberships message_membership_as
          ON message_membership_as.id = message_profile_as.brand_membership_id
        INNER JOIN profiles message_profile_bs
          ON message_profile_bs.id = matches.profile_b_id AND message_profile_bs.brand_id = conversations.brand_id
        INNER JOIN users message_user_bs ON message_user_bs.id = message_profile_bs.user_id
        INNER JOIN brand_memberships message_membership_bs
          ON message_membership_bs.id = message_profile_bs.brand_membership_id
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
