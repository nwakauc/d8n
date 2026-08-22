module Notifications
  class EventPublisher
    def self.membership_registered!(membership:)
      return unless Policy.handles?(brand: membership.brand, event_type: "membership_registered")

      NotificationEvent.create_or_find_by!(
        idempotency_key: "membership_registered:#{membership.id}"
      ) do |event|
        event.brand = membership.brand
        event.user = membership.user
        event.brand_membership = membership
        event.event_type = "membership_registered"
        event.payload = {}
        event.occurred_at = Time.current
      end
    end
  end
end
