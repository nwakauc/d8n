module Notifications
  module Email
    # Test double: captures what would have been sent so specs can assert recipient
    # and rendered content without a network call or Action Mailer's delivery array.
    class TestGateway
      PROVIDER = "test".freeze

      class << self
        def configured? = true

        def deliveries
          @deliveries ||= []
        end

        def clear
          deliveries.clear
        end

        def deliver(brand:, recipient:, code:, mailer_action:, delivery:, idempotency_key: nil)
          message = Email.build_message(brand:, recipient:, code:, mailer_action:)
          deliveries << {
            to: recipient,
            subject: message.subject,
            text: message.text_part&.body&.to_s,
            html: message.html_part&.body&.to_s,
            idempotency_key:,
            delivery_id: delivery.id
          }
          DeliveryResponse.ok(provider: PROVIDER, external_id: "test-#{delivery.id}")
        end
      end
    end
  end
end
