module Notifications
  class DeliverProductNotificationJob < ApplicationJob
    class TransientDeliveryError < StandardError; end

    queue_as :default

    retry_on TransientDeliveryError, wait: :polynomially_longer, attempts: 5

    def perform(delivery_id)
      delivery = NotificationDelivery.find_by(id: delivery_id)
      return unless claim(delivery)

      response = deliver(delivery)
      record_response(delivery, response)
      raise TransientDeliveryError if response.retryable
    rescue TransientDeliveryError
      raise
    rescue StandardError => error
      record_unexpected_failure(delivery, error)
      raise
    end

    private

    def claim(delivery)
      return false unless delivery&.notification

      delivery.with_lock do
        return false if delivery.sent? || delivery.skipped? || delivery.processing?
        unless eligible_recipient?(delivery.notification)
          delivery.update!(
            status: :skipped,
            error_code: "recipient_unavailable",
            error_message: "The brand membership is no longer eligible for product delivery"
          )
          return false
        end

        delivery.update!(
          status: :processing,
          attempt_count: delivery.attempt_count + 1,
          last_attempted_at: Time.current,
          error_code: nil,
          error_message: nil
        )
      end
      true
    end

    def eligible_recipient?(notification)
      membership = notification.brand_membership
      membership.deleted_at.nil? && membership.active? && notification.user.deleted_at.nil? &&
        notification.user.active? && notification.brand.deleted_at.nil? && notification.brand.active?
    end

    def deliver(delivery)
      case delivery.channel
      when "email" then deliver_email(delivery)
      when "push" then deliver_push(delivery)
      else
        DeliveryResponse.permanent(
          provider: delivery.provider,
          error_code: "unsupported_channel",
          error_message: "Product delivery channel is unsupported"
        )
      end
    end

    def deliver_email(delivery)
      notification = delivery.notification
      from_address = Email.product_from_address(notification.brand)
      return missing_email_sender(delivery) if from_address.blank?

      message = Email.build_product_message(
        notification:,
        recipient: delivery.recipient,
        from_address:
      )
      Email.gateway.deliver(
        brand: notification.brand,
        recipient: delivery.recipient,
        code: nil,
        mailer_action: nil,
        delivery:,
        idempotency_key: delivery.idempotency_key,
        message:,
        from_address:
      )
    end

    def deliver_push(delivery)
      device = delivery.device_registration
      return unavailable_device(delivery) unless device&.enabled? && device.revoked_at.nil? && device.deleted_at.nil?

      definition = Types.fetch(delivery.notification.notification_type)
      Push.gateway.deliver(
        token: device.token,
        title: definition.title,
        body: definition.body,
        data: {
          notification_id: delivery.notification.public_id,
          notification_type: delivery.notification.notification_type
        },
        delivery:,
        idempotency_key: delivery.idempotency_key
      )
    end

    def missing_email_sender(delivery)
      DeliveryResponse.permanent(
        provider: delivery.provider,
        error_code: "sender_not_configured",
        error_message: "No product email sender is configured for this brand."
      )
    end

    def unavailable_device(delivery)
      DeliveryResponse.permanent(
        provider: delivery.provider,
        error_code: "device_unavailable",
        error_message: "The push device is no longer deliverable."
      )
    end

    def record_response(delivery, response)
      attributes = {
        provider: response.provider,
        external_id: response.external_id,
        error_code: response.error_code,
        error_message: response.error_message,
        metadata: delivery.metadata.merge("retryable" => response.retryable)
      }
      if response.success?
        attributes.merge!(status: :sent, sent_at: Time.current, failed_at: nil)
      else
        attributes.merge!(status: :failed, failed_at: Time.current)
      end
      delivery.update!(attributes)
    end

    def record_unexpected_failure(delivery, error)
      return unless delivery&.persisted?

      delivery.update_columns(
        status: NotificationDelivery.statuses.fetch("failed"),
        error_code: error.class.name,
        error_message: "Unexpected product notification delivery failure",
        failed_at: Time.current,
        updated_at: Time.current
      )
    end
  end
end
