module Notifications
  # The single, provider-agnostic result any email/SMS gateway returns. Domains and
  # senders speak this shape and never see vendor payloads. `retryable` is the
  # contract the async delivery worker needs: it distinguishes a transient provider
  # hiccup (network error, timeout, HTTP 429/5xx) that a bounded retry may fix from
  # a permanent failure (invalid recipient) or an auth/config failure that retrying
  # cannot fix. `external_id` is the provider's message id for later correlation.
  DeliveryResponse = Data.define(:success?, :provider, :external_id, :error_code, :error_message, :retryable) do
    def self.ok(provider:, external_id:)
      new(success?: true, provider:, external_id:, error_code: nil, error_message: nil, retryable: false)
    end

    def self.transient(provider:, error_code: "transient_error", error_message: "Delivery provider unavailable")
      new(success?: false, provider:, external_id: nil, error_code:, error_message:, retryable: true)
    end

    def self.permanent(provider:, error_code:, error_message:)
      new(success?: false, provider:, external_id: nil, error_code:, error_message:, retryable: false)
    end
  end
end
