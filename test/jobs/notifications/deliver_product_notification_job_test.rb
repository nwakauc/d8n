require "test_helper"

module Notifications
  class DeliverProductNotificationJobTest < ActiveJob::TestCase
    include ActiveJob::TestHelper

    setup do
      @brand = Brand.create!(slug: "dateza", name: "DateZA")
      @user = User.create!
      @membership = BrandMembership.create!(brand: @brand, user: @user, status: :active)
      @user.identity_identifiers.create!(
        kind: :email,
        normalized_value: "welcome@example.com",
        last_seen_at: Time.current
      )
      @event = EventPublisher.membership_registered!(membership: @membership)
      ProcessEventJob.perform_now(@event.id)
      Email::TestGateway.clear
      Push::TestGateway.clear
      clear_enqueued_jobs
    end

    test "welcome email uses the DateZA template and a brand sender exactly once" do
      delivery = @event.notification.notification_deliveries.email.sole

      with_env("D8N_EMAIL_PROVIDER" => "test", "D8N_DATEZA_EMAIL_FROM" => "DateZA <hello@dateza.test>") do
        2.times { DeliverProductNotificationJob.perform_now(delivery.id) }
      end

      assert delivery.reload.sent?
      assert_equal 1, delivery.attempt_count
      assert_equal 1, Email::TestGateway.deliveries.length
      message = Email::TestGateway.deliveries.sole
      assert_equal "Welcome to DateZA", message.fetch(:subject)
      assert_equal "DateZA <hello@dateza.test>", message.fetch(:from)
      assert_includes message.fetch(:text), "Complete your profile"
      assert_equal "product-notification:#{@event.notification.id}:email", message.fetch(:idempotency_key)
    end

    test "a transient email failure is tracked and can be retried on the same delivery" do
      delivery = @event.notification.notification_deliveries.email.sole
      calls = 0
      gateway = Class.new do
        define_singleton_method(:deliver) do |**|
          calls += 1
          if calls == 1
            DeliveryResponse.transient(provider: "fake", error_code: "timeout", error_message: "Provider unavailable")
          else
            DeliveryResponse.ok(provider: "fake", external_id: "email-123")
          end
        end
      end

      with_env("D8N_DATEZA_EMAIL_FROM" => "DateZA <hello@dateza.test>") do
        stub_method(Email, :gateway, -> { gateway }) do
          assert_enqueued_jobs 1, only: DeliverProductNotificationJob do
            DeliverProductNotificationJob.perform_now(delivery.id)
          end
          assert delivery.reload.failed?
          assert_equal true, delivery.metadata.fetch("retryable")

          DeliverProductNotificationJob.perform_now(delivery.id)
        end
      end

      assert delivery.reload.sent?
      assert_equal 2, delivery.attempt_count
      assert_equal "email-123", delivery.external_id
    end

    test "an eligible brand-owned device receives privacy-safe push" do
      device = DeviceRegistration.create!(
        brand: @brand,
        user: @user,
        brand_membership: @membership,
        platform: :ios,
        token: "private-device-token",
        last_seen_at: Time.current
      )
      # Reprocess a fresh event because channel selection happens at materialization.
      second_event = NotificationEvent.create!(
        brand: @brand,
        user: @user,
        brand_membership: @membership,
        event_type: "membership_registered",
        idempotency_key: "membership_registered:test-device:#{@membership.id}",
        payload: {},
        occurred_at: Time.current
      )
      ProcessEventJob.perform_now(second_event.id)
      delivery = second_event.notification.notification_deliveries.push.sole

      with_env("D8N_PUSH_PROVIDER" => "test") do
        DeliverProductNotificationJob.perform_now(delivery.id)
      end

      pushed = Push::TestGateway.deliveries.sole
      assert_equal device.token, pushed.fetch(:token)
      assert_equal "Welcome to DateZA", pushed.fetch(:title)
      assert_not_includes pushed.to_json, "welcome@example.com"
      assert_not_includes delivery.recipient, "private-device-token"
    end

    test "no device or a revoked device creates no push attempt" do
      assert_equal 0, @event.notification.notification_deliveries.push.count

      DeviceRegistration.create!(
        brand: @brand,
        user: @user,
        brand_membership: @membership,
        platform: :android,
        token: "revoked-token",
        enabled: false,
        revoked_at: Time.current,
        last_seen_at: Time.current
      )
      second_event = NotificationEvent.create!(
        brand: @brand,
        user: @user,
        brand_membership: @membership,
        event_type: "membership_registered",
        idempotency_key: "membership_registered:revoked:#{@membership.id}",
        payload: {},
        occurred_at: Time.current
      )
      ProcessEventJob.perform_now(second_event.id)

      assert_equal 0, second_event.notification.notification_deliveries.push.count
    end

    test "product preferences suppress email and push without suppressing in-app" do
      NotificationPreference.create!(
        brand: @brand,
        user: @user,
        brand_membership: @membership,
        product_email_enabled: false,
        push_enabled: false
      )
      DeviceRegistration.create!(
        brand: @brand,
        user: @user,
        brand_membership: @membership,
        platform: :ios,
        token: "preference-device-token",
        last_seen_at: Time.current
      )
      event = NotificationEvent.create!(
        brand: @brand,
        user: @user,
        brand_membership: @membership,
        event_type: "membership_registered",
        idempotency_key: "membership_registered:preferences:#{@membership.id}",
        payload: {},
        occurred_at: Time.current
      )

      ProcessEventJob.perform_now(event.id)

      assert_equal 1, event.notification.notification_deliveries.in_app.count
      assert_equal 0, event.notification.notification_deliveries.email.count
      assert_equal 0, event.notification.notification_deliveries.push.count
    end

    test "a membership closed before provider work is skipped" do
      delivery = @event.notification.notification_deliveries.email.sole
      @membership.update!(status: :left)

      with_env("D8N_EMAIL_PROVIDER" => "test") do
        DeliverProductNotificationJob.perform_now(delivery.id)
      end

      assert delivery.reload.skipped?
      assert_equal "recipient_unavailable", delivery.error_code
      assert_empty Email::TestGateway.deliveries
    end

    private

    def with_env(values)
      previous = values.to_h { |key, _value| [ key, ENV[key] ] }
      values.each { |key, value| ENV[key] = value }
      yield
    ensure
      previous.each { |key, value| ENV[key] = value }
    end
  end
end
