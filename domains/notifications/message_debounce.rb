module Notifications
  # Repeated message_received activity in the same conversation collapses into
  # a single email/push delivery instead of one per message — five quick
  # messages should read as "you have a new message", not five separate
  # interruptions. In-app notifications (the inbox badge/list) and the
  # conversation's own message list are untouched: every message still shows
  # up there immediately. This only suppresses redundant INTERRUPTIVE
  # (email/push) delivery for the same conversation while an earlier one from
  # that conversation is still sitting in its debounce delay.
  module MessageDebounce
    WINDOW = 90.seconds
    EVENT_TYPE = "message_received"

    def self.applicable?(event_type)
      event_type == EVENT_TYPE
    end

    # True when an undelivered email/push for the same brand+user+channel+
    # conversation was already queued within the debounce window — the
    # eventual send of THAT delivery covers this later message too, so no
    # new delivery row is needed for it.
    def self.suppress?(brand:, user:, channel:, conversation_id:)
      return false if conversation_id.blank?

      NotificationDelivery.pending.joins(:notification)
        .where(brand:, user:, channel:, created_at: WINDOW.ago..)
        .where("notifications.payload -> 'target' ->> 'type' = 'conversation'")
        .where("notifications.payload -> 'target' ->> 'id' = ?", conversation_id)
        .exists?
    end
  end
end
