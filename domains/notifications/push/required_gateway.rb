module Notifications
  module Push
    # No APNs/FCM provider has been approved. Production therefore records a clear,
    # permanent configuration failure instead of pretending a device was reached.
    class RequiredGateway
      PROVIDER = "required".freeze

      def self.configured? = false

      def self.deliver(token:, title:, body:, data:, delivery:, idempotency_key:)
        DeliveryResponse.permanent(
          provider: PROVIDER,
          error_code: "provider_not_configured",
          error_message: "No push provider is configured for this brand."
        )
      end
    end
  end
end
