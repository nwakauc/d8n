require "test_helper"

module Hq
  module TrustSafety
    class OverviewTest < ActiveSupport::TestCase
      setup do
        @brand = Brand.create!(slug: "hq-ts-overview", name: "HQ TS Overview")
        @reporter = create_profile("Reporter")
        @reported = create_profile("Reported")
      end

      test "returns truthful brand-scoped queue and enforcement counts without inventing an SLA" do
        oldest = create_report(status: :open, reason: :harassment, target_type: :profile)
        oldest.update_columns(created_at: Time.utc(2026, 8, 29, 10, 0, 0))
        create_report(status: :reviewing, reason: :spam, target_type: :message, target_id: 12)
        create_report(status: :dismissed, reason: :harassment, target_type: :profile)

        admin = AdminUser.create!(user: User.create!, status: :active)
        AccountEnforcement.create!(
          brand: @brand, user: @reported.user, brand_membership: @reported.brand_membership,
          profile: @reported, admin_user: admin, reason: "reviewed"
        )

        result = Overview.call(brand: @brand, as_of: Time.utc(2026, 8, 29, 10, 5, 0))

        assert_equal @brand.slug, result.brand
        assert_equal 3, result.report_count
        assert_equal({ "open" => 1, "reviewing" => 1, "actioned" => 0, "dismissed" => 1 }, result.counts_by_status)
        assert_equal 2, result.awaiting_decision_count
        assert_equal oldest.created_at, result.oldest_open_report_at
        assert_equal 300, result.oldest_open_report_age_seconds
        assert_equal 2, result.counts_by_reason.fetch("harassment")
        assert_equal 1, result.counts_by_target_type.fetch("message")
        assert_equal "not_configured", result.sla_status
        assert_nil result.overdue_count
        assert_equal 1, result.enforcement_count
        assert_equal 1, result.active_enforcement_count
      end

      test "does not include another brand" do
        create_report(status: :open, reason: :spam, target_type: :profile)
        other_brand = Brand.create!(slug: "hq-ts-overview-other", name: "Other")
        other_reporter = create_profile("Other Reporter", brand: other_brand)
        other_reported = create_profile("Other Reported", brand: other_brand)
        Report.create!(
          brand: other_brand, reporter_profile: other_reporter, reported_profile: other_reported,
          reason: :spam, target_type: :profile, status: :open
        )

        assert_equal 1, Overview.call(brand: @brand).report_count
      end

      private

      def create_profile(name, brand: @brand)
        user = User.create!
        membership = BrandMembership.create!(brand:, user:)
        Profile.create!(
          brand:, user:, brand_membership: membership, display_name: name,
          birthdate: 30.years.ago.to_date, gender: "person", status: :active, visibility: :visible
        )
      end

      def create_report(status:, reason:, target_type:, target_id: nil)
        Report.create!(
          brand: @brand, reporter_profile: @reporter, reported_profile: @reported,
          status:, reason:, target_type:, target_id:
        )
      end
    end
  end
end
