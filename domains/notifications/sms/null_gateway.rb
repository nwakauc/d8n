module Notifications
  module Sms
    class NullGateway
      def self.deliver(...)
        new.deliver(...)
      end

      def deliver(to:, body:, brand:, delivery:)
        Response.new(true, "null", "null-#{delivery.id}", nil, nil)
      end
    end
  end
end
