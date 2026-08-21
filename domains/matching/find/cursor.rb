module Matching
  module Find
    class Cursor
      class Invalid < StandardError; end

      PURPOSE = "find-cursor-v1"

      class << self
        def encode(brand:, membership:, policy:, filter:, profile:)
          verifier.generate(
            {
              brand: brand.slug,
              membership: membership.id,
              policy: policy.key,
              filter: filter.cursor_key,
              created_at: profile.created_at.iso8601(6),
              profile: profile.public_id
            },
            purpose: PURPOSE
          )
        end

        def apply(scope:, value:, brand:, membership:, policy:, filter:)
          return scope if value.blank?

          payload = verifier.verify(value, purpose: PURPOSE).with_indifferent_access
          validate_context!(payload:, brand:, membership:, policy:, filter:)
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

        private

        def verifier
          Rails.application.message_verifier(PURPOSE)
        end

        def validate_context!(payload:, brand:, membership:, policy:, filter:)
          return if payload[:brand] == brand.slug && payload[:membership] == membership.id &&
            payload[:policy] == policy.key && payload[:filter] == filter.cursor_key

          raise Invalid, "cursor is invalid"
        end
      end
    end
  end
end
