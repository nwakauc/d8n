require "test_helper"

module Hq
  module TrustSafety
    class EnforcementHistoryTest < ActiveSupport::TestCase
      setup do
        @brand = Brand.create!(slug: "hq-ts-enforcements", name: "HQ TS Enforcements")
        @admin = AdminUser.create!(user: User.create!, status: :active)
      end

      test "paginates newest-first and filters by state" do
        active_one = create_enforcement("Active one")
        reverted = create_enforcement("Reverted", reverted_at: Time.current)
        active_two = create_enforcement("Active two")
        active_one.update_columns(created_at: 3.hours.ago)
        reverted.update_columns(created_at: 2.hours.ago)
        active_two.update_columns(created_at: 1.hour.ago)

        first_page = EnforcementHistory.call(brand: @brand, limit: 2)
        second_page = EnforcementHistory.call(brand: @brand, limit: 2, cursor: first_page.next_cursor)

        assert_equal [ active_two.id, reverted.id ], first_page.enforcements.map(&:id)
        assert_equal [ active_one.id ], second_page.enforcements.map(&:id)

        active = EnforcementHistory.call(brand: @brand, state: "active")
        assert_equal [ active_two.id, active_one.id ], active.enforcements.map(&:id)
      end

      test "cursor is bound to the state filter and brand" do
        2.times { |index| create_enforcement("Target #{index}") }
        cursor = EnforcementHistory.call(brand: @brand, state: "active", limit: 1).next_cursor

        assert_raises(EnforcementCursor::Invalid) do
          EnforcementHistory.call(brand: @brand, state: "reverted", cursor:, limit: 1)
        end

        other_brand = Brand.create!(slug: "hq-ts-enforcements-other", name: "Other")
        assert_raises(EnforcementCursor::Invalid) do
          EnforcementHistory.call(brand: other_brand, state: "active", cursor:, limit: 1)
        end
      end

      test "rejects invalid filters and limits" do
        error = assert_raises(HqError) { EnforcementHistory.call(brand: @brand, state: "all") }
        assert_equal :invalid_filter, error.code

        error = assert_raises(HqError) { EnforcementHistory.call(brand: @brand, limit: 101) }
        assert_equal :invalid_limit, error.code
      end

      private

      def create_enforcement(name, reverted_at: nil)
        user = User.create!
        membership = BrandMembership.create!(brand: @brand, user:)
        profile = Profile.create!(
          brand: @brand, user:, brand_membership: membership, display_name: name,
          birthdate: 30.years.ago.to_date, gender: "person", status: :active, visibility: :visible
        )
        AccountEnforcement.create!(
          brand: @brand, user:, brand_membership: membership, profile:, admin_user: @admin,
          reason: "test", reverted_at:
        )
      end
    end
  end
end
