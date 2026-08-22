module Notifications
  module Email
    # Production default when no real email provider is selected. Reports "not
    # configured" so the calling domain fails closed instead of pretending to send.
    class RequiredGateway
      PROVIDER = "required".freeze

      def self.configured? = false

      def self.deliver(brand:, recipient:, code:, mailer_action:, delivery:, idempotency_key: nil,
        message: nil, from_address: nil)
        DeliveryResponse.permanent(
          provider: PROVIDER,
          error_code: "provider_not_configured",
          error_message: "No email provider is configured for #{brand.slug}."
        )
      end
    end
  end
end
