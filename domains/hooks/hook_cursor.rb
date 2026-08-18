module Hooks
  # Signed, brand+viewer-bound cursor for the received-Hook inbox. Mirrors
  # Messaging::MessageCursor: newest-first by (created_at DESC, id DESC), opaque
  # and tamper-proof, with the internal row id as a stable monotonic tiebreak
  # (safe to embed because the token is signed).
  class HookCursor
    class Invalid < StandardError; end

    PURPOSE = "hook-inbox-cursor"

    def self.encode(brand:, viewer:, hook:)
      verifier.generate(
        {
          brand: brand.slug,
          viewer: viewer.public_id,
          created_at: hook.created_at.iso8601(6),
          id: hook.id
        },
        purpose: PURPOSE
      )
    end

    def self.apply(scope:, value:, brand:, viewer:)
      return scope if value.blank?

      payload = verifier.verify(value, purpose: PURPOSE).with_indifferent_access
      raise Invalid, "cursor is invalid" unless payload[:brand] == brand.slug && payload[:viewer] == viewer.public_id

      created_at = Time.iso8601(payload.fetch(:created_at))
      id = Integer(payload.fetch(:id))

      scope.where(
        "hooks.created_at < ? OR (hooks.created_at = ? AND hooks.id < ?)",
        created_at, created_at, id
      )
    rescue ActiveSupport::MessageVerifier::InvalidSignature, ArgumentError, KeyError, TypeError
      raise Invalid, "cursor is invalid"
    end

    def self.verifier
      Rails.application.message_verifier(PURPOSE)
    end
    private_class_method :verifier
  end
end
