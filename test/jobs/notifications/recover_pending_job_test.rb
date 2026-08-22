require "test_helper"

module Notifications
  class RecoverPendingJobTest < ActiveJob::TestCase
    include ActiveJob::TestHelper

    setup do
      @brand = Brand.create!(slug: "dateza", name: "DateZA")
      @user = User.create!
      @membership = BrandMembership.create!(brand: @brand, user: @user, status: :active)
      @event = EventPublisher.membership_registered!(membership: @membership)
      clear_enqueued_jobs
    end

    test "re-enqueues an event whose after-commit enqueue was missed" do
      assert_enqueued_with(job: ProcessEventJob, args: [ @event.id ]) do
        RecoverPendingJob.perform_now
      end
    end

    test "recovers a stale in-progress delivery using its existing idempotency key" do
      ProcessEventJob.perform_now(@event.id)
      delivery = @event.notification.notification_deliveries.email
        .create!(
          brand: @brand,
          user: @user,
          provider: "test",
          recipient: "welcome@example.com",
          idempotency_key: "stale-delivery-test",
          status: :processing,
          attempt_count: 1,
          last_attempted_at: 20.minutes.ago
        )
      clear_enqueued_jobs

      assert_enqueued_with(job: DeliverProductNotificationJob, args: [ delivery.id ]) do
        RecoverPendingJob.perform_now
      end

      assert delivery.reload.failed?
      assert_equal "stale_processing", delivery.error_code
      assert_equal true, delivery.metadata.fetch("retryable")
      assert_equal "stale-delivery-test", delivery.idempotency_key
    end
  end
end
