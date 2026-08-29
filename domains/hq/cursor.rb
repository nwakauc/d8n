module Hq
  # Signed, member-bound cursor for HQ history reads (security events, auth
  # attempts, enforcements). Ordered newest-first; a cursor pages backward into
  # older rows. Bound to brand + user + purpose so a cursor cannot be replayed
  # against another member, another brand, or another resource type.
  class Cursor
    class Invalid < StandardError; end

    def self.encode(purpose:, brand:, user:, record:)
      verifier.generate(
        {
          brand: brand.slug,
          user_id: user.id,
          created_at: record.created_at.iso8601(6),
          id: record.id
        },
        purpose: purpose
      )
    end

    def self.apply(scope:, purpose:, value:, brand:, user:, table:)
      return scope if value.blank?

      payload = verifier.verify(value, purpose: purpose).with_indifferent_access
      raise Invalid, "cursor is invalid" unless payload[:brand] == brand.slug && payload[:user_id] == user.id

      created_at = Time.iso8601(payload.fetch(:created_at))
      id = Integer(payload.fetch(:id))

      scope.where(
        "#{table}.created_at < ? OR (#{table}.created_at = ? AND #{table}.id < ?)",
        created_at, created_at, id
      )
    rescue ActiveSupport::MessageVerifier::InvalidSignature, ArgumentError, KeyError, TypeError
      raise Invalid, "cursor is invalid"
    end

    def self.verifier
      Rails.application.message_verifier("hq-history-cursor")
    end
    private_class_method :verifier
  end
end
