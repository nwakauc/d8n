module Notifications
  module Sms
    # Development default: accepts and drops the message. Considered "configured"
    # so local flows exercise the full path without a vendor.
    class NullGateway
      def self.configured? = true

      def self.deliver(...)
        new.deliver(...)
      end

      def deliver(to:, body:, brand:, delivery:)
        DeliveryResponse.ok(provider: "null", external_id: "null-#{delivery.id}")
      end
    end
  end
end
