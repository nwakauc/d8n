require "test_helper"

module Hq
  module TrustSafety
    class RepeatOffendersTest < ActiveSupport::TestCase
      setup do
        @brand = Brand.create!(slug: "hq-ts-repeat", name: "HQ TS Repeat")
        @reporter = create_profile("Reporter")
      end

      test "returns only repeatedly reported profiles ordered by report count" do
        most_reported = create_profile("Most")
        repeated = create_profile("Repeated")
        single = create_profile("Single")

        3.times { create_report(most_reported, reporter: create_profile("Reporter")) }
        2.times { create_report(repeated, reporter: create_profile("Reporter")) }
        create_report(single)

        result = RepeatOffenders.call(brand: @brand)

        assert_equal 2, result.minimum_reports
        assert_not result.truncated
        assert_equal [ most_reported.public_id, repeated.public_id ], result.offenders.map(&:profile_id)
        assert_equal [ 3, 2 ], result.offenders.map(&:report_count)
        assert_equal [ 3, 2 ], result.offenders.map(&:awaiting_decision_count)
        assert_equal most_reported.public_id, result.offenders.first.member_360_lookup
      end

      test "is brand-scoped and bounded" do
        first = create_profile("First")
        second = create_profile("Second")
        2.times { create_report(first, reporter: create_profile("Reporter")) }
        2.times { create_report(second, reporter: create_profile("Reporter")) }

        other_brand = Brand.create!(slug: "hq-ts-repeat-other", name: "Other")
        other_target = create_profile("Other Target", brand: other_brand)
        3.times do
          Report.create!(
            brand: other_brand, reporter_profile: create_profile("Other Reporter", brand: other_brand),
            reported_profile: other_target,
            reason: :spam, target_type: :profile, status: :open
          )
        end

        result = RepeatOffenders.call(brand: @brand, limit: 1)

        assert_equal 1, result.offenders.size
        assert result.truncated
        assert_not_equal other_target.public_id, result.offenders.first.profile_id
      end

      test "rejects an invalid limit" do
        error = assert_raises(HqError) { RepeatOffenders.call(brand: @brand, limit: 0) }
        assert_equal :invalid_limit, error.code
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

      def create_report(reported_profile, reporter: @reporter)
        Report.create!(
          brand: @brand, reporter_profile: reporter, reported_profile:,
          reason: :harassment, target_type: :profile, status: :open
        )
      end
    end
  end
end
