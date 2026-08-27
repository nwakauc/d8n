module Notifications
  module Sms
    # Development default: accepts and drops the message. Considered "configured"
    # so local flows exercise the full path without a vendor.
    class NullGateway
      def self.configured?(brand:) = true
      def self.configuration_error_code(brand:) = nil

      def self.deliver(...)
        new.deliver(...)
      end

      def deliver(to:, body:, brand:, delivery:)
        DeliveryResponse.ok(provider: "null", external_id: "null-#{delivery.id}")
      end
    end
  end
end
