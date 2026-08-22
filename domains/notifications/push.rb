module Notifications
  module Push
    def self.gateway
      provider_name == "test" ? TestGateway : RequiredGateway
    end

    def self.provider_name
      ENV.fetch("D8N_PUSH_PROVIDER", Rails.env.test? ? "test" : "required")
    end

    def self.configured?
      gateway.configured?
    end
  end
end
