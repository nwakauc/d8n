module Notifications
  module Sms
    # Backwards-compatible alias: every SMS gateway returns the shared,
    # provider-agnostic DeliveryResponse (see Notifications::DeliveryResponse).
    Response = DeliveryResponse

    def self.gateway
      case provider_name
      when "null"
        NullGateway
      when "test"
        TestGateway
      when "twilio"
        TwilioGateway
      else
        RequiredGateway
      end
    end

    def self.provider_name
      ENV.fetch("D8N_SMS_PROVIDER", Rails.env.production? ? "required" : "null")
    end

    # Cheap, network-free readiness check used by the OTP/recovery/verification
    # domains BEFORE they enqueue async delivery, so a misconfigured provider fails
    # closed at request time (503 / silent) instead of enqueuing a doomed job.
    def self.configured?
      gateway.configured?
    end
  end
end
