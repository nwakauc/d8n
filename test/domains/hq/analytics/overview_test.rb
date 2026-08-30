require "test_helper"

module Hq
  module Analytics
    class OverviewTest < ActiveSupport::TestCase
      test "computes brand-scoped signup, activity, and gender metrics" do
        brand = Brand.create!(slug: "analytics-brand", name: "Analytics Brand")
        now = Time.utc(2026, 8, 30, 10, 0, 0) # 12:00 Africa/Johannesburg, Sunday
        today = create_member(brand:, gender: "woman", joined_at: now - 2.hours)
        week = create_member(brand:, gender: "man", joined_at: now - 2.days)
        month = create_member(brand:, gender: "person", joined_at: Time.utc(2026, 8, 2, 10, 0, 0))
        unknown = create_member(brand:, gender: nil, joined_at: now - 40.days)

        create_session(today, brand:, last_used_at: now - 1.hour)
        create_session(week, brand:, last_used_at: now - 2.days)
        create_session(month, brand:, last_used_at: now - 8.days)
        create_session(unknown, brand:, last_used_at: now - 31.days)
        other_brand = Brand.create!(slug: "analytics-other", name: "Other")
        create_member(brand: other_brand, gender: "woman", joined_at: now)

        result = Overview.call(brand:, now:)

        assert_equal "Africa/Johannesburg", result.time_zone
        assert_equal 1, result.signups_today
        assert_equal 1, result.signups_this_week
        assert_equal 3, result.signups_this_month
        assert_equal 1, result.active_today
        assert_equal 2, result.active_7d
        assert_equal 3, result.active_30d
        assert_equal({ woman: 1, man: 1, other: 1, unknown: 1 }, result.gender_split)
        assert_equal 4, result.total_registered_members
      end

      private

      def create_member(brand:, gender:, joined_at:)
        user = User.create!
        membership = BrandMembership.create!(brand:, user:)
        membership.update_columns(created_at: joined_at)
        profile = Profile.create!(
          brand:, user:, brand_membership: membership, display_name: "Member",
          birthdate: 30.years.ago.to_date, gender:, status: :active, visibility: :visible
        )
        profile
      end

      def create_session(profile, brand:, last_used_at:)
        _token, session = Session.issue!(user: profile.user, brand:)
        session.update_columns(last_used_at:)
      end
    end
  end
end
