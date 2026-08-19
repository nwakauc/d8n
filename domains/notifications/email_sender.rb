module Notifications
  # Records a NotificationDelivery attempt, then delegates the actual send to the
  # configured email gateway (Notifications::Email). Provider-independent: it never
  # references Resend/SES/SMTP directly. `retryable` is propagated from the gateway
  # so the async delivery worker can distinguish a transient failure from a
  # permanent one.
  class EmailSender
    Result = Data.define(:success?, :delivery, :retryable)

    def self.call(...)
      new(...).call
    end

    def initialize(brand:, recipient:, code:, user:, mailer_action: :verification_code, metadata: {}, idempotency_key: nil)
      @brand = brand
      @recipient = recipient
      @code = code
      @user = user
      @mailer_action = mailer_action
      @metadata = metadata
      @idempotency_key = idempotency_key
    end

    def call
      delivery = NotificationDelivery.create!(
        brand:,
        user:,
        channel: :email,
        provider: Email.provider_name,
        recipient:,
        status: :pending,
        metadata:
      )

      response = Email.gateway.deliver(
        brand:, recipient:, code:, mailer_action:, delivery:, idempotency_key:
      )
      update_delivery(delivery, response)

      Result.new(response.success?, delivery, response.retryable)
    end

    private

    attr_reader :brand, :recipient, :code, :user, :mailer_action, :metadata, :idempotency_key

    def update_delivery(delivery, response)
      if response.success?
        delivery.update!(
          status: :sent,
          provider: response.provider,
          external_id: response.external_id,
          sent_at: Time.current
        )
      else
        delivery.update!(
          status: :failed,
          provider: response.provider,
          error_code: response.error_code,
          error_message: response.error_message,
          failed_at: Time.current
        )
      end
    end
  end
end
