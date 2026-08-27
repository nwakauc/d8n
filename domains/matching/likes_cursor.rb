module Matching
  # Opaque, signed cursor shared by Matching::IncomingLikes and
  # Matching::OutgoingLikes. Like has no public_id of its own, so the tie-break
  # key is the OTHER profile's public_id — unique per viewer within one
  # direction because a profile can have at most one active Like toward
  # another (idx_likes_active_pair). `direction` is bound into the signed
  # payload so an incoming cursor can never be replayed against the outgoing
  # endpoint or vice versa, mirroring how Matching::Cursor binds strategy/filter.
  class LikesCursor
    class Invalid < StandardError; end

    PURPOSE = "likes-list-cursor"

    def self.encode(brand:, viewer:, direction:, created_at:, counterpart:)
      verifier.generate(
        {
          brand: brand.slug,
          viewer: viewer.public_id,
          direction: direction.to_s,
          created_at: created_at.iso8601(6),
          profile: counterpart.public_id
        },
        purpose: PURPOSE
      )
    end

    # `scope` must already join the counterpart profile aliased as `profiles`
    # (i.e. `.joins(:liker_profile)` or `.joins(:liked_profile)`), matching the
    # ordering each caller applies (`likes.created_at DESC, profiles.public_id DESC`).
    def self.apply(scope:, value:, brand:, viewer:, direction:)
      return scope if value.blank?

      payload = verifier.verify(value, purpose: PURPOSE).with_indifferent_access
      validate_payload!(payload:, brand:, viewer:, direction:)
      created_at = Time.iso8601(payload.fetch(:created_at))
      public_id = payload.fetch(:profile).to_s
      raise Invalid, "cursor is invalid" unless public_id.match?(Profile::PUBLIC_ID_FORMAT)

      scope.where(
        "likes.created_at < :created_at OR (likes.created_at = :created_at AND profiles.public_id < :public_id)",
        created_at:, public_id:
      )
    rescue ActiveSupport::MessageVerifier::InvalidSignature, ArgumentError, KeyError, TypeError
      raise Invalid, "cursor is invalid"
    end

    def self.verifier
      Rails.application.message_verifier(PURPOSE)
    end
    private_class_method :verifier

    def self.validate_payload!(payload:, brand:, viewer:, direction:)
      return if payload[:brand] == brand.slug && payload[:viewer] == viewer.public_id &&
        payload[:direction] == direction.to_s

      raise Invalid, "cursor is invalid"
    end
    private_class_method :validate_payload!
  end
end
