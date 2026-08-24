module Hooks
  # The recipient's inbox of live (pending, unexpired) Hooks, newest-first and
  # cursor-paginated. Only Hooks whose sender is still visible to the viewer are
  # returned: sender availability, both block directions, suspension, closure, and
  # brand isolation are all delegated to Matching::VisibilityScope (the same rule
  # discovery uses), so a blocked/suspended/closed sender silently drops off and
  # nothing about them leaks. Sender profiles/photos/options are preloaded so the
  # serialized inbox has no N+1.
  class ReceivedInbox
    DEFAULT_LIMIT = 20
    MAX_LIMIT = 50

    class InvalidLimit < StandardError; end

    Result = Data.define(:hooks, :viewer, :next_cursor)

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
      scope = Hook.live
        .where(brand:, recipient_profile: viewer)
        .where(sender_profile_id: Matching::VisibilityScope.call(brand:, viewer:).select(:id))
        .order("hooks.created_at DESC", "hooks.id DESC")
      scope = HookCursor.apply(scope:, value: cursor, brand:, viewer:)
      hooks = scope.includes(sender_profile: [
        :brand,
        { profile_option_selections: [ :profile_option, :profile_option_group ] },
        { profile_photos: { display_image_attachment: :blob } }
      ]).limit(limit + 1).to_a
      has_more = hooks.length > limit
      hooks = hooks.first(limit)

      Result.new(
        hooks:,
        viewer:,
        next_cursor: has_more ? HookCursor.encode(brand:, viewer:, hook: hooks.last) : nil
      )
    rescue Matching::InteractionError
      raise Messaging::AccessError, :profile_unavailable
    end

    private

    attr_reader :user, :brand, :cursor, :limit

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
