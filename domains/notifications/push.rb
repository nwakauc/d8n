module Notifications
  module Push
    def self.gateway
      case provider_name
      when "test" then TestGateway
      when "expo" then ExpoGateway
      else RequiredGateway
      end
    end

    def self.provider_name
      ENV.fetch("D8N_PUSH_PROVIDER", Rails.env.test? ? "test" : "required")
    end

    def self.configured?
      gateway.configured?
    end
  end
end
