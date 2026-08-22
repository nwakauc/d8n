module Notifications
  class MaterializeEvent
    def self.call(...)
      new(...).call
    end

    def initialize(event:)
      @event = event
    end

    def call
      event.with_lock do
        return event.notification if event.processed_at?

        event.increment!(:processing_attempts)
        plan = Policy.plan_for(event)
        return finish_without_notification unless plan && eligible_membership?

        notification = create_notification(plan)
        create_in_app_delivery(notification)
        create_email_delivery(notification) if Policy.channel_allowed?(membership:, category: :product_email)
        create_push_deliveries(notification) if Policy.channel_allowed?(membership:, category: :push)
        event.update!(processed_at: Time.current, last_error_code: nil)
        notification
      end
    rescue StandardError => error
      event.update_columns(last_error_code: error.class.name, updated_at: Time.current) if event.persisted?
      raise
    end

    private

    attr_reader :event

    delegate :brand_membership, to: :event, private: true
    alias_method :membership, :brand_membership

    def eligible_membership?
      membership.deleted_at.nil? && membership.active? && event.user.deleted_at.nil? && event.user.active? &&
        event.brand.deleted_at.nil? && event.brand.active?
    end

    def create_notification(plan)
      Notification.create_or_find_by!(notification_event: event) do |notification|
        notification.brand = event.brand
        notification.user = event.user
        notification.brand_membership = membership
        notification.notification_type = plan.notification_type
        notification.payload = {}
      end
    end

    def create_in_app_delivery(notification)
      NotificationDelivery.create_or_find_by!(idempotency_key: delivery_key(notification, "in_app")) do |delivery|
        delivery.notification = notification
        delivery.brand = event.brand
        delivery.user = event.user
        delivery.channel = :in_app
        delivery.provider = "database"
        delivery.recipient = "membership:#{membership.id}"
        delivery.status = :sent
        delivery.external_id = notification.public_id
        delivery.attempt_count = 1
        delivery.last_attempted_at = Time.current
        delivery.sent_at = Time.current
        delivery.metadata = { notification_type: notification.notification_type }
      end
    end

    def create_email_delivery(notification)
      recipient = preferred_email
      return unless recipient

      NotificationDelivery.create_or_find_by!(idempotency_key: delivery_key(notification, "email")) do |delivery|
        delivery.notification = notification
        delivery.brand = event.brand
        delivery.user = event.user
        delivery.channel = :email
        delivery.provider = Email.provider_name
        delivery.recipient = recipient
        delivery.status = :pending
        delivery.metadata = { notification_type: notification.notification_type }
      end
    end

    def create_push_deliveries(notification)
      DeviceRegistration.deliverable.where(
        brand: event.brand,
        user: event.user,
        brand_membership: membership
      ).find_each do |device|
        NotificationDelivery.create_or_find_by!(
          idempotency_key: delivery_key(notification, "push", device.id)
        ) do |delivery|
          delivery.notification = notification
          delivery.device_registration = device
          delivery.brand = event.brand
          delivery.user = event.user
          delivery.channel = :push
          delivery.provider = Push.provider_name
          delivery.recipient = "device:#{device.public_id}"
          delivery.status = :pending
          delivery.metadata = {
            notification_type: notification.notification_type,
            platform: device.platform
          }
        end
      end
    end

    def preferred_email
      event.user.identity_identifiers.kept.email
        .order(Arel.sql("verified_at DESC NULLS LAST, last_seen_at DESC NULLS LAST, id ASC"))
        .pick(:normalized_value)
    end

    def delivery_key(notification, channel, target = nil)
      [ "product-notification", notification.id, channel, target ].compact.join(":")
    end

    def finish_without_notification
      event.update!(processed_at: Time.current, last_error_code: nil)
      nil
    end
  end
end
