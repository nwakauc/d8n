module Notifications
  module Sms
    class TestGateway
      class << self
        def configured?(brand:) = true
        def configuration_error_code(brand:) = nil

        def deliveries
          @deliveries ||= []
        end

        def clear
          deliveries.clear
        end

        def deliver(...)
          new.deliver(...)
        end
      end

      def deliver(to:, body:, brand:, delivery:)
        self.class.deliveries << {
          to:,
          body:,
          brand_id: brand.id,
          delivery_id: delivery.id
        }

        DeliveryResponse.ok(provider: "test", external_id: "test-#{delivery.id}")
      end
    end
  end
end
