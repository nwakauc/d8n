require "test_helper"

module Date9ja
  module Import
    class TrustLedgerImportTest < ActiveSupport::TestCase
      setup do
        @brand = Brand.create!(slug: "date9ja", name: "Date9ja")
        @alice = profile("alice", "woman")
        bind(:user, "1", @alice.user)
        bind(:profile, "1", @alice)
      end

      test "re-projects already-imported trust history rows into TrustEvent/TrustAdjustment and is idempotent" do
        source = Snapshot::ExtendedHistorySource.new(rows: {
          trust_events: [
            { id: 50, user_id: 1, event_type: "email_verified", points: 25, source_type: "IdentityIdentifier", created_at: 3.days.ago },
            { id: 51, user_id: 1, event_type: "phone_verified", points: 50, created_at: 2.days.ago }
          ],
          trust_adjustments: [
            { id: 60, user_id: 1, actor_id: 999, points: -20, reason_code: "policy_violation",
              appeal_status: "not_requested", created_at: 1.day.ago }
          ],
          entitlements: [ { id: 1, trust_xp: 55 } ]
        })
        ExtendedHistoryImport.call(brand: @brand, source:)

        result = TrustLedgerImport.call(brand: @brand)

        assert_equal 3, result.imported
        assert_equal 0, result.failed
        assert_equal 2, TrustEvent.where(brand: @brand, user: @alice.user).count
        adjustment = TrustAdjustment.find_by!(brand: @brand, user: @alice.user)
        assert_equal(-20, adjustment.points)
        assert_equal "policy_violation", adjustment.reason_code
        assert_equal "not_requested", adjustment.appeal_status
        assert_equal 999, adjustment.metadata.fetch("legacy_actor_id")
        assert_nil adjustment.actor_admin_user_id

        assert_equal 55, Trust::Ledger.score(user: @alice.user, brand: @brand)

        second = TrustLedgerImport.call(brand: @brand)
        assert_equal 0, second.imported
        assert_equal 3, second.skipped
        assert_equal 2, TrustEvent.count
        assert_equal 1, TrustAdjustment.count
      end

      test "an overturned adjustment is preserved but excluded from the score" do
        source = Snapshot::ExtendedHistorySource.new(rows: {
          trust_events: [
            { id: 52, user_id: 1, event_type: "email_verified", points: 25, created_at: 3.days.ago }
          ],
          trust_adjustments: [
            { id: 61, user_id: 1, points: -10, reason_code: "policy_violation",
              appeal_status: "overturned", created_at: 1.day.ago }
          ]
        })
        ExtendedHistoryImport.call(brand: @brand, source:)

        TrustLedgerImport.call(brand: @brand)

        assert_equal 25, Trust::Ledger.score(user: @alice.user, brand: @brand)
        breakdown = Trust::Ledger.breakdown(user: @alice.user, brand: @brand)
        overturned_entry = breakdown.find { |entry| entry.fetch(:type) == "policy_violation" }
        assert_not overturned_entry.fetch(:applies)
      end

      private

      def profile(name, gender)
        user = User.create!
        membership = BrandMembership.create!(brand: @brand, user:)
        Profile.create!(brand: @brand, user:, brand_membership: membership,
          display_name: name, birthdate: 30.years.ago.to_date, gender:)
      end

      def bind(entity, source_id, destination)
        args = { source_system: "date9ja", source_entity: entity.to_s, source_id:,
                 destination:, importer_version: "fixture" }
        args[:brand] = @brand unless destination.is_a?(User)
        Migration::ReferenceMap.bind!(**args)
      end
    end
  end
end
