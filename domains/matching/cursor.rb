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
          profile: profile.public_id,
          ranking: strategy.cursor_payload(profile:)
        },
        purpose: PURPOSE
      )
    end

    def self.apply(scope:, value:, brand:, strategy:)
      return scope if value.blank?

      payload = verifier.verify(value, purpose: PURPOSE).with_indifferent_access
      validate_payload!(payload:, brand:, strategy:)
      strategy.apply_cursor(scope:, payload: payload.fetch(:ranking).merge(
        created_at: payload.fetch(:created_at),
        profile: payload.fetch(:profile)
      ))
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
