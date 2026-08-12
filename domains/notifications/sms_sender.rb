module Notifications
  class SmsSender
    Result = Data.define(:success?, :delivery)

    def self.call(...)
      new(...).call
    end

    def initialize(brand:, recipient:, body:, user: nil, metadata: {})
      @brand = brand
      @recipient = recipient
      @body = body
      @user = user
      @metadata = metadata
    end

    def call
      delivery = NotificationDelivery.create!(
        brand:,
        user:,
        channel: :sms,
        provider: gateway_name,
        recipient:,
        status: :pending,
        metadata:
      )

      response = Sms.gateway.deliver(to: recipient, body:, brand:, delivery:)
      update_delivery(delivery, response)

      Result.new(response.success?, delivery)
    end

    private

    attr_reader :brand, :recipient, :body, :user, :metadata

    def gateway_name
      ENV.fetch("D8N_SMS_PROVIDER", Rails.env.production? ? "required" : "null")
    end

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
