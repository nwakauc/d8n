module Notifications
  module Push
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

        def deliver(token:, title:, body:, data:, delivery:, idempotency_key:)
          deliveries << {
            token:,
            title:,
            body:,
            data:,
            delivery_id: delivery.id,
            idempotency_key:
          }
          DeliveryResponse.ok(provider: PROVIDER, external_id: "test-push-#{delivery.id}")
        end
      end
    end
  end
end
