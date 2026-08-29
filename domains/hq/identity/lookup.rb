module Hq
  module Identity
    # Resolves a member within one brand by email, phone, or profile public_id.
    # Returns nil for anything that doesn't resolve to a kept BrandMembership on
    # this brand -- cross-brand identifiers, unknown values, and malformed input
    # are all indistinguishable "not found", so this can never be used to probe
    # whether an identifier exists on a brand the caller isn't assigned to.
    class Lookup
      Result = Data.define(:user, :brand_membership, :profile)

      def self.call(brand:, lookup:)
        new(brand:, lookup:).call
      end

      def initialize(brand:, lookup:)
        @brand = brand
        @lookup = lookup.to_s.strip
      end

      def call
        return if lookup.blank?

        profile = resolve_profile
        user = profile&.user || resolve_user_by_identifier
        return if user.blank?

        membership = BrandMembership.kept.find_by(brand:, user:)
        return if membership.blank?

        Result.new(user:, brand_membership: membership, profile: profile || current_profile(membership))
      end

      private

      attr_reader :brand, :lookup

      def resolve_profile
        return unless lookup.match?(Profile::PUBLIC_ID_FORMAT)

        brand.profiles.kept.find_by(public_id: lookup)
      end

      def resolve_user_by_identifier
        identifier = ::Identity::LoginIdentifier.call(lookup, brand:)
        return if identifier.blank?

        ::IdentityIdentifier.kept
          .where(kind: identifier.kind, normalized_value: identifier.lookup_values)
          .first&.user
      end

      def current_profile(membership)
        brand.profiles.kept.find_by(brand_membership: membership)
      end
    end
  end
end
