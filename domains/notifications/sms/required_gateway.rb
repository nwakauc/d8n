module Notifications
  module Sms
    class RequiredGateway
      def self.deliver(...)
        new.deliver(...)
      end

      def deliver(to:, body:, brand:, delivery:)
        Response.new(
          false,
          "required",
          nil,
          "provider_not_configured",
          "No SMS provider is configured for #{brand.slug}."
        )
      end
    end
  end
end
