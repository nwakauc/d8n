module Matching
  class MatchCursor
    class Invalid < StandardError; end

    PURPOSE = "match-list-cursor"

    def self.encode(brand:, viewer:, match:)
      verifier.generate(
        {
          brand: brand.slug,
          viewer: viewer.public_id,
          created_at: match.created_at.iso8601(6),
          match: match.public_id
        },
        purpose: PURPOSE
      )
    end

    def self.apply(scope:, value:, brand:, viewer:)
      return scope if value.blank?

      payload = verifier.verify(value, purpose: PURPOSE).with_indifferent_access
      validate_payload!(payload:, brand:, viewer:)
      created_at = Time.iso8601(payload.fetch(:created_at))
      public_id = payload.fetch(:match).to_s
      raise Invalid, "cursor is invalid" unless public_id.match?(Profile::PUBLIC_ID_FORMAT)

      scope.where(
        "matches.created_at < ? OR (matches.created_at = ? AND matches.public_id < ?)",
        created_at, created_at, public_id
      )
    rescue ActiveSupport::MessageVerifier::InvalidSignature, ArgumentError, KeyError, TypeError
      raise Invalid, "cursor is invalid"
    end

    def self.verifier
      Rails.application.message_verifier(PURPOSE)
    end
    private_class_method :verifier

    def self.validate_payload!(payload:, brand:, viewer:)
      return if payload[:brand] == brand.slug && payload[:viewer] == viewer.public_id

      raise Invalid, "cursor is invalid"
    end
    private_class_method :validate_payload!
  end
end
