module Hq
  # Signed cursor for the brand-scoped member directory. The cursor is bound
  # to the brand and membership-status filter so it cannot be replayed across
  # tenants or filters.
  class MemberDirectoryCursor
    class Invalid < StandardError; end

    PURPOSE = "hq-member-directory-cursor"

    def self.encode(brand:, status:, membership:)
      verifier.generate(
        {
          brand: brand.slug,
          status: status,
          created_at: membership.created_at.iso8601(6),
          id: membership.id
        },
        purpose: PURPOSE
      )
    end

    def self.apply(scope:, value:, brand:, status:)
      return scope if value.blank?

      payload = verifier.verify(value, purpose: PURPOSE).with_indifferent_access
      raise Invalid unless payload[:brand] == brand.slug && payload[:status] == status

      created_at = Time.iso8601(payload.fetch(:created_at))
      id = Integer(payload.fetch(:id))
      scope.where(
        "brand_memberships.created_at < ? OR (brand_memberships.created_at = ? AND brand_memberships.id < ?)",
        created_at, created_at, id
      )
    rescue ActiveSupport::MessageVerifier::InvalidSignature, ArgumentError, KeyError, TypeError
      raise Invalid
    end

    def self.verifier
      Rails.application.message_verifier("hq-member-directory-cursor")
    end
    private_class_method :verifier
  end
end
