module Matching
  class Cursor
    class Invalid < StandardError; end

    PURPOSE = "discovery-cursor"

    def self.encode(brand:, strategy:, profile:)
      verifier.generate(
        {
          brand: brand.slug,
          strategy: strategy.key,
          created_at: profile.created_at.iso8601(6),
          profile: profile.public_id
        },
        purpose: PURPOSE
      )
    end

    def self.apply(scope:, value:, brand:, strategy:)
      return scope if value.blank?

      payload = verifier.verify(value, purpose: PURPOSE).with_indifferent_access
      validate_payload!(payload:, brand:, strategy:)
      created_at = Time.iso8601(payload.fetch(:created_at))
      public_id = payload.fetch(:profile).to_s
      raise Invalid, "cursor is invalid" unless public_id.match?(Profile::PUBLIC_ID_FORMAT)

      scope.where(
        "profiles.created_at < ? OR (profiles.created_at = ? AND profiles.public_id < ?)",
        created_at, created_at, public_id
      )
    rescue ActiveSupport::MessageVerifier::InvalidSignature, ArgumentError, KeyError, TypeError
      raise Invalid, "cursor is invalid"
    end

    def self.verifier
      Rails.application.message_verifier(PURPOSE)
    end
    private_class_method :verifier

    def self.validate_payload!(payload:, brand:, strategy:)
      return if payload[:brand] == brand.slug && payload[:strategy] == strategy.key

      raise Invalid, "cursor is invalid"
    end
    private_class_method :validate_payload!
  end
end
