module Notifications
  module Sms
    Response = Data.define(:success?, :provider, :external_id, :error_code, :error_message)

    def self.gateway
      gateway_name = ENV.fetch("D8N_SMS_PROVIDER", Rails.env.production? ? "required" : "null")

      case gateway_name
      when "null"
        NullGateway
      when "test"
        TestGateway
      else
        RequiredGateway
      end
    end
  end
end
