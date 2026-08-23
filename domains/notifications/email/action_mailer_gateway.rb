module Notifications
  module Email
    # Development/self-hosted SMTP path: sends through Action Mailer's configured
    # delivery method. Any delivery exception is treated as transient (SMTP hiccups
    # are usually retryable); permanent classification is left to real API providers.
    class ActionMailerGateway
      PROVIDER = "action_mailer".freeze

      def self.configured?(brand:) = Email.from_address(brand).present?

      def self.deliver(brand:, recipient:, code:, mailer_action:, delivery:, idempotency_key: nil,
        message: nil, from_address: nil)
        (message || Email.build_message(brand:, recipient:, code:, mailer_action:)).deliver_now
        DeliveryResponse.ok(provider: PROVIDER, external_id: "action_mailer-#{delivery.id}")
      rescue StandardError => e
        DeliveryResponse.transient(provider: PROVIDER, error_code: e.class.name, error_message: "SMTP delivery failed")
      end
    end
  end
end
