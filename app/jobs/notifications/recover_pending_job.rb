module Notifications
  # Safety net for the durable outbox if enqueueing fails after commit. It only
  # re-enqueues records that have never begun delivery; Active Job owns retries
  # once an actual provider attempt has started.
  class RecoverPendingJob < ApplicationJob
    queue_as :default

    BATCH_SIZE = 100
    STALE_AFTER = 15.minutes

    def perform
      NotificationEvent.where(processed_at: nil).order(:id).limit(BATCH_SIZE).pluck(:id).each do |event_id|
        ProcessEventJob.perform_later(event_id)
      end

      NotificationDelivery.where(status: :pending).where.not(notification_id: nil)
        .order(:id).limit(BATCH_SIZE).pluck(:id).each do |delivery_id|
          DeliverProductNotificationJob.perform_later(delivery_id)
        end

      recover_stale_deliveries
    end

    private

    def recover_stale_deliveries
      NotificationDelivery.where(status: :processing).where.not(notification_id: nil)
        .where(last_attempted_at: ...STALE_AFTER.ago).order(:id).limit(BATCH_SIZE).find_each do |delivery|
          delivery.update!(
            status: :failed,
            error_code: "stale_processing",
            error_message: "Delivery worker ended before recording an outcome",
            failed_at: Time.current,
            metadata: delivery.metadata.merge("retryable" => true)
          )
          DeliverProductNotificationJob.perform_later(delivery.id)
        end
    end
  end
end
