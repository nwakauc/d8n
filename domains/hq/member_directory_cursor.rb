module Hq
  # Signed cursor for the brand-scoped member directory. The cursor is bound
  # to the brand and complete query so it cannot be replayed across tenants,
  # filters, or sort modes.
  class MemberDirectoryCursor
    class Invalid < StandardError; end

    PURPOSE = "hq-member-directory-cursor"

    def self.encode(brand:, query:, sort:, membership:)
      verifier.generate(
        {
          brand: brand.slug,
          query: query.to_json,
          sort:,
          created_at: membership.created_at.iso8601(6),
          last_active_at: membership.last_active_at&.iso8601(6),
          id: membership.id
        },
        purpose: PURPOSE
      )
    end

    def self.apply(scope:, value:, brand:, query:, sort:)
      return scope if value.blank?

      payload = verifier.verify(value, purpose: PURPOSE).with_indifferent_access
      raise Invalid unless payload[:brand] == brand.slug && payload[:query] == query.to_json && payload[:sort] == sort

      id = Integer(payload.fetch(:id))

      if sort == "oldest"
        created_at = Time.iso8601(payload.fetch(:created_at))
        return scope.where(
          "brand_memberships.created_at > ? OR (brand_memberships.created_at = ? AND brand_memberships.id > ?)",
          created_at, created_at, id
        )
      end

      if sort == "recently_active"
        last_active_at = payload[:last_active_at].present? ? Time.iso8601(payload[:last_active_at]) : nil
        return scope.where("#{Hq::MemberDirectory::LAST_ACTIVE_SQL} IS NULL AND brand_memberships.id < ?", id) if last_active_at.nil?

        return scope.where(
          "#{Hq::MemberDirectory::LAST_ACTIVE_SQL} < :last_active_at OR " \
            "(#{Hq::MemberDirectory::LAST_ACTIVE_SQL} = :last_active_at AND brand_memberships.id < :id) OR " \
            "#{Hq::MemberDirectory::LAST_ACTIVE_SQL} IS NULL",
          last_active_at:, id:
        )
      end

      created_at = Time.iso8601(payload.fetch(:created_at))
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
