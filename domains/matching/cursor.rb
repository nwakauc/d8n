module Matching
  class Cursor
    class Invalid < StandardError; end

    PURPOSE = "discovery-cursor"

    def self.encode(brand:, strategy:, profile:, filter: nil)
      verifier.generate(
        {
          brand: brand.slug,
          strategy: strategy.key,
          filter: filter_key(filter),
          created_at: profile.created_at.iso8601(6),
          profile: profile.public_id,
          ranking: strategy.cursor_payload(profile:)
        },
        purpose: PURPOSE
      )
    end

    def self.apply(scope:, value:, brand:, strategy:, filter: nil)
      return scope if value.blank?

      payload = verifier.verify(value, purpose: PURPOSE).with_indifferent_access
      validate_payload!(payload:, brand:, strategy:, filter:)
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

    def self.validate_payload!(payload:, brand:, strategy:, filter:)
      return if payload[:brand] == brand.slug && payload[:strategy] == strategy.key &&
        payload[:filter].to_s == filter_key(filter)

      raise Invalid, "cursor is invalid"
    end
    private_class_method :validate_payload!

    # Cursors predating facet filtering carry no `filter` key; `nil.to_s == ""`
    # keeps them valid for unfiltered requests.
    def self.filter_key(filter)
      filter.respond_to?(:cursor_key) ? filter.cursor_key : ""
    end
    private_class_method :filter_key
  end
end
