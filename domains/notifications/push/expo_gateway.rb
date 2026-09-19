module Notifications
  module Push
    # Expo Push Service is the provider used by the current Date9ja native app.
    # Expo's ticket vocabulary stays inside this provider boundary.
    class ExpoGateway
      ENDPOINT = "https://exp.host/--/api/v2/push/send".freeze
      PROVIDER = "expo".freeze
      DISABLING_ERRORS = %w[DeviceNotRegistered].freeze
      TRANSIENT_ERRORS = %w[MessageRateExceeded].freeze

      class << self
        def configured? = true

        def deliver(token:, title:, body:, data:, delivery:, idempotency_key:)
          response = HttpClient.post_json(
            ENDPOINT,
            headers: headers,
            payload: { to: token, sound: "default", title:, body:, data: }
          )
          classify(response)
        rescue HttpClient::TransientError
          DeliveryResponse.transient(provider: PROVIDER, error_message: "Expo Push Service unavailable")
        end

        private

        def headers
          return {} if ENV["D8N_EXPO_ACCESS_TOKEN"].blank?

          { "Authorization" => "Bearer #{ENV.fetch("D8N_EXPO_ACCESS_TOKEN")}" }
        end

        def classify(response)
          unless response.success?
            return transient_http(response) if [ 429, 500, 502, 503, 504 ].include?(response.status)

            return DeliveryResponse.permanent(provider: PROVIDER, error_code: "http_#{response.status}",
              error_message: "Expo Push Service rejected the request")
          end

          ticket = Array(response.json["data"]).first
          return malformed_response unless ticket.is_a?(Hash)
          return DeliveryResponse.ok(provider: PROVIDER, external_id: ticket["id"]) if ticket["status"] == "ok"

          classify_ticket_error(ticket)
        end

        def classify_ticket_error(ticket)
          provider_error = ticket.dig("details", "error").presence || "ProviderError"
          return DeliveryResponse.transient(provider: PROVIDER, error_code: "rate_limited",
            error_message: "Expo Push Service rate limited the delivery") if TRANSIENT_ERRORS.include?(provider_error)
          return DeliveryResponse.permanent(provider: PROVIDER, error_code: "invalid_token",
            error_message: "Expo rejected the device token") if DISABLING_ERRORS.include?(provider_error)

          DeliveryResponse.permanent(provider: PROVIDER, error_code: "provider_rejected",
            error_message: "Expo Push Service rejected the delivery")
        end

        def transient_http(response)
          DeliveryResponse.transient(provider: PROVIDER, error_code: "http_#{response.status}",
            error_message: "Expo Push Service temporarily unavailable")
        end

        def malformed_response
          DeliveryResponse.transient(provider: PROVIDER, error_code: "invalid_provider_response",
            error_message: "Expo Push Service returned an invalid response")
        end
      end
    end
  end
end
