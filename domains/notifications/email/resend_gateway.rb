module Notifications
  module Email
    # Production transactional email via Resend's HTTP API. Only this class knows
    # about Resend; everything else speaks EmailSender + DeliveryResponse.
    #
    # Idempotency: Resend honours an Idempotency-Key header (cached ~24h), so a
    # worker retry after a mid-flight crash cannot send a second copy. The key is
    # derived from the challenge (stable across retries), not the per-attempt
    # delivery row.
    class ResendGateway
      ENDPOINT = "https://api.resend.com/emails".freeze
      PROVIDER = "resend".freeze

      class << self
        def configured? = api_key.present? && from_address.present?

        def api_key = ENV["RESEND_API_KEY"].presence
        def from_address = ENV["D8N_EMAIL_FROM"].presence

        def deliver(brand:, recipient:, code:, mailer_action:, delivery:, idempotency_key: nil)
          return not_configured(brand) unless configured?

          message = Email.build_message(brand:, recipient:, code:, mailer_action:)
          response = HttpClient.post_json(
            ENDPOINT,
            headers: headers(idempotency_key),
            payload: {
              from: from_address,
              to: [ recipient ],
              subject: message.subject,
              html: message.html_part&.body&.to_s,
              text: message.text_part&.body&.to_s
            }.compact
          )
          classify(response)
        rescue HttpClient::TransientError
          DeliveryResponse.transient(provider: PROVIDER, error_message: "Resend unavailable")
        end

        private

        def headers(idempotency_key)
          base = { "Authorization" => "Bearer #{api_key}" }
          base["Idempotency-Key"] = idempotency_key if idempotency_key.present?
          base
        end

        def classify(response)
          return DeliveryResponse.ok(provider: PROVIDER, external_id: response.json["id"]) if response.success?

          code = response.json["name"].presence || "http_#{response.status}"
          if [ 429, 500, 502, 503, 504 ].include?(response.status)
            DeliveryResponse.transient(provider: PROVIDER, error_code: code, error_message: "Resend transient error")
          else
            # 4xx (invalid address, auth). Retrying will not help; the raw provider
            # message is never surfaced upstream, only a generic category.
            DeliveryResponse.permanent(provider: PROVIDER, error_code: code, error_message: "Resend rejected the email")
          end
        end

        def not_configured(brand)
          DeliveryResponse.permanent(
            provider: PROVIDER,
            error_code: "provider_not_configured",
            error_message: "Resend is not configured for #{brand.slug}."
          )
        end
      end
    end
  end
end
