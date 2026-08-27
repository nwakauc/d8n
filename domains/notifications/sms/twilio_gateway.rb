module Notifications
  module Sms
    # Production SMS via Twilio's Messages API. This is the only place that knows
    # anything about Twilio; the rest of D8N speaks SmsSender + DeliveryResponse.
    #
    # Authentication: a Twilio Standard API Key (not the master Account Auth Token).
    # The REST call is HTTP Basic with username = API Key SID, password = API Key
    # Secret, while the request path still scopes to the Account SID.
    #
    # Sender: resolved per brand so one Twilio account can serve multiple brands
    # without HookUs-specific logic leaking into the domain. For a brand with slug
    # "hookus" this reads TWILIO_HOOKUS_MESSAGING_SERVICE_SID, falling back to a
    # generic messaging service or a from number. Using a Messaging Service (rather
    # than a hardcoded number) lets Twilio pick the attached sender.
    #
    # Recipient formatting: D8N's canonical phone (Identity::PhoneNormalizer) is
    # digits-only including country code, e.g. "27821234567"; Twilio requires
    # +E.164, so we prepend "+" here rather than inventing a second phone format.
    #
    # Idempotency: Twilio's Messages endpoint has no general idempotency-key, so
    # duplicate suppression across worker retries relies on D8N clearing the
    # challenge's delivery_code the moment a send succeeds (see DeliverChallengeJob).
    class TwilioGateway
      PROVIDER = "twilio".freeze

      class << self
        # Readiness includes the resolved brand sender because a globally valid
        # Twilio account cannot send for a brand with no Messaging Service/From.
        def configured?(brand:) = configuration_error_code(brand:).nil?

        def configuration_error_code(brand:)
          return "provider_not_configured" unless account_configured?
          "sender_not_configured" if sender(brand).blank?
        end

        def account_configured? = account_sid.present? && api_key_sid.present? && api_key_secret.present?

        def account_sid = ENV["TWILIO_ACCOUNT_SID"].presence
        def api_key_sid = ENV["TWILIO_API_KEY_SID"].presence
        # The Standard API Key secret. Stored under TWILIO_CLIENT_SECRET to match
        # the established production environment (Twilio calls this the API Key Secret).
        def api_key_secret = ENV["TWILIO_CLIENT_SECRET"].presence

        # Generic brand -> Messaging Service mapping (e.g. hookus ->
        # TWILIO_HOOKUS_MESSAGING_SERVICE_SID), then generic fallbacks.
        def messaging_service_sid(brand)
          ENV["TWILIO_#{brand.slug.upcase}_MESSAGING_SERVICE_SID"].presence ||
            ENV["TWILIO_MESSAGING_SERVICE_SID"].presence
        end

        def from_number = ENV["TWILIO_FROM_NUMBER"].presence

        def sender(brand) = messaging_service_sid(brand) || from_number

        def deliver(...)
          new.deliver(...)
        end
      end

      def deliver(to:, body:, brand:, delivery:)
        return not_configured(brand) unless self.class.account_configured?
        return no_sender(brand) if self.class.sender(brand).blank?

        response = HttpClient.post_form(
          "https://api.twilio.com/2010-04-01/Accounts/#{self.class.account_sid}/Messages.json",
          headers: { "Authorization" => basic_auth },
          form: message_params(to:, body:, brand:)
        )
        classify(response)
      rescue HttpClient::TransientError
        DeliveryResponse.transient(provider: PROVIDER, error_message: "Twilio unavailable")
      end

      private

      def message_params(to:, body:, brand:)
        params = { "To" => e164(to, brand:), "Body" => body }
        if (service_sid = self.class.messaging_service_sid(brand))
          params["MessagingServiceSid"] = service_sid
        else
          params["From"] = self.class.from_number
        end
        params
      end

      def e164(value, brand:)
        calling_code = Identity::PhonePolicy.country_calling_code(brand:)
        normalized = Identity::PhoneNormalizer.call(value, country_calling_code: calling_code)
        "+#{normalized}"
      end

      # HTTP Basic with the Standard API Key SID/secret pair.
      def basic_auth
        token = [ "#{self.class.api_key_sid}:#{self.class.api_key_secret}" ].pack("m0")
        "Basic #{token}"
      end

      def classify(response)
        return DeliveryResponse.ok(provider: PROVIDER, external_id: response.json["sid"]) if response.success?

        code = response.json["code"]&.to_s || "http_#{response.status}"
        if [ 429, 500, 502, 503, 504 ].include?(response.status)
          DeliveryResponse.transient(provider: PROVIDER, error_code: code, error_message: "Twilio transient error")
        else
          # 4xx (invalid recipient, auth) — retrying will not help. Message text is
          # intentionally generic; the raw provider body is never surfaced upstream.
          DeliveryResponse.permanent(provider: PROVIDER, error_code: code, error_message: "Twilio rejected the message")
        end
      end

      def not_configured(brand)
        DeliveryResponse.permanent(
          provider: PROVIDER,
          error_code: "provider_not_configured",
          error_message: "Twilio is not configured for #{brand.slug}."
        )
      end

      def no_sender(brand)
        DeliveryResponse.permanent(
          provider: PROVIDER,
          error_code: "sender_not_configured",
          error_message: "No Twilio sender is configured for #{brand.slug}."
        )
      end
    end
  end
end
