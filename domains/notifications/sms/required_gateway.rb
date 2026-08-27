module Notifications
  module Sms
    # Production default when no real SMS provider is selected. Reports "not
    # configured" so the calling domain fails closed rather than pretending to send.
    class RequiredGateway
      def self.configured?(brand:) = false
      def self.configuration_error_code(brand:) = "provider_not_configured"

      def self.deliver(...)
        new.deliver(...)
      end

      def deliver(to:, body:, brand:, delivery:)
        DeliveryResponse.permanent(
          provider: "required",
          error_code: "provider_not_configured",
          error_message: "No SMS provider is configured for #{brand.slug}."
        )
      end
    end
  end
end
