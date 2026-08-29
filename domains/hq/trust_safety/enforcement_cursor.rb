module Hq
  module TrustSafety
    # Signed cursor for brand-wide enforcement history. It is bound to both the
    # brand and state filter so it cannot be replayed into another view.
    class EnforcementCursor
      class Invalid < StandardError; end

      PURPOSE = "hq-trust-safety-enforcement-cursor"

      def self.encode(brand:, state:, enforcement:)
        verifier.generate(
          {
            brand: brand.slug,
            state: state.to_s,
            created_at: enforcement.created_at.iso8601(6),
            id: enforcement.id
          },
          purpose: PURPOSE
        )
      end

      def self.apply(scope:, value:, brand:, state:)
        return scope if value.blank?

        payload = verifier.verify(value, purpose: PURPOSE).with_indifferent_access
        unless payload[:brand] == brand.slug && payload[:state] == state.to_s
          raise Invalid, "cursor is invalid"
        end

        created_at = Time.iso8601(payload.fetch(:created_at))
        id = Integer(payload.fetch(:id))

        scope.where(
          "account_enforcements.created_at < ? OR " \
          "(account_enforcements.created_at = ? AND account_enforcements.id < ?)",
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
end
