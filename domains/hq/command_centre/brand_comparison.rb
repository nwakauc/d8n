module Hq
  module CommandCentre
    # Founder-safe multi-brand comparison. Only brands with an active admin
    # assignment and hq.analytics.read on that assignment are included.
    class BrandComparison
      Result = Data.define(:generated_at, :time_zone, :brands)

      def self.call(admin_user:, now: Time.current)
        new(admin_user:, now:).call
      end

      def initialize(admin_user:, now:)
        @admin_user = admin_user
        @now = now
      end

      def call
        brands = assignments.filter_map { |assignment| brand_entry(assignment) }

        Result.new(
          generated_at: now,
          time_zone: ::Hq::Metrics::Windows::TIME_ZONE,
          brands:
        )
      end

      private

      attr_reader :admin_user, :now

      def assignments
        AdminAssignment.kept.active.includes(:brand, :admin_role).joins(:brand, :admin_role)
          .where(admin_user:)
          .where(admin_roles: { name: ::Admin::Capabilities::ROLE_NAMES, deleted_at: nil })
          .where(brands: { status: Brand.statuses.fetch("active"), deleted_at: nil })
          .order("brands.slug")
      end

      def brand_entry(assignment)
        brand = assignment.brand
        capabilities = assignment.admin_role.capabilities

        return unless capabilities.include?(::Admin::Capabilities::ANALYTICS_READ)

        snapshot = BrandHealthSnapshot.call(brand:, now:)

        {
          brand: brand.slug,
          accessible: true,
          role: assignment.admin_role.name,
          brand_health: snapshot.brand_health
        }
      end
    end
  end
end
