module Notifications
  module Sms
    class TestGateway
      class << self
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

        Response.new(true, "test", "test-#{delivery.id}", nil, nil)
      end
    end
  end
end
