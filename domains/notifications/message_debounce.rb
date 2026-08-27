module Notifications
  # Leading-edge send, trailing-edge suppression: the FIRST message in a burst
  # gets its email/push immediately (no artificial delay — a lone message must
  # never wait on this), and any further message_received activity in the same
  # conversation within the debounce window is suppressed rather than queued,
  # so five quick messages produce one interruption, not five. In-app
  # notifications (the inbox badge/list) and the conversation's own message
  # list are untouched — every message still shows up there immediately.
  #
  # The eventual delivery's title/body is always Notifications::Types' static,
  # generic template ("New message" — see domains/notifications/types.rb),
  # never a copy of message text, so there is no "stale content" risk from a
  # suppressed later message being the one that would have "said more" — the
  # notification never quotes message content regardless of which one in the
  # burst it is tied to.
  module MessageDebounce
    WINDOW = 90.seconds
    EVENT_TYPE = "message_received"
    SUPPRESSING_STATUSES = %w[pending processing sent].freeze

    def self.applicable?(event_type)
      event_type == EVENT_TYPE
    end

    # True when an email/push for the same brand+user+channel+conversation was
    # already queued or sent within the debounce window — that one already
    # interrupted the recipient (or is about to), so this later message adds
    # nothing and gets no delivery of its own.
    def self.suppress?(brand:, user:, channel:, conversation_id:)
      return false if conversation_id.blank?

      NotificationDelivery.where(status: SUPPRESSING_STATUSES).joins(:notification)
        .where(brand:, user:, channel:, created_at: WINDOW.ago..)
        .where("notifications.payload -> 'target' ->> 'type' = 'conversation'")
        .where("notifications.payload -> 'target' ->> 'id' = ?", conversation_id)
        .exists?
    end
  end
end
