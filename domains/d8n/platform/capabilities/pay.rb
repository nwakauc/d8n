module D8n
  module Platform
    module Capabilities
      module Pay
        DEFINITIONS = %w[
          pay.plan
          pay.entitlement
          pay.subscription
          pay.payment
          pay.marketplace
        ].map { |key| CapabilityDefinition.new(key:, status: :planned) }.freeze

        def self.definitions = DEFINITIONS
      end
    end
  end
end
