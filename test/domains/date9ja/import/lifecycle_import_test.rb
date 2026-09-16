require "test_helper"

module Date9ja
  module Import
    class LifecycleImportTest < ActiveSupport::TestCase
      setup do
        @brand = Brand.create!(slug: "date9ja", name: "Date9ja")
        @retained = profile("retained", "woman")
        Migration::ReferenceMap.bind!(source_system: "date9ja", source_entity: "user", source_id: "1",
          destination: @retained.user, importer_version: "fixture")
      end

      test "writes an identity tombstone for a soft-deleted member without resurrecting a user" do
        source = Snapshot::LifecycleSource.new(rows: [
          { id: 2, public_id: "d9-2", deleted_at: 3.days.ago, deletion_reason: "left",
            deletion_reason_code: 4, deletion_comment: "moving on" }
        ])
        result = LifecycleImport.call(brand: @brand, source:)
        assert_equal 1, result.reconciliation.count(:identity_tombstone, :imported)

        record = Date9jaHistoryRecord.find_by!(source_entity: "identity_tombstone", source_id: "2")
        assert_nil record.user
        assert_equal "deleted", record.status
        assert_equal "left", record.payload["deletion_reason"]
        assert_equal 0, User.where(id: nil).count

        assert_equal 1, LifecycleImport.call(brand: @brand, source:).reconciliation.count(:identity_tombstone, :already_imported)
      end

      test "records moderation state with actor context for a retained restricted member" do
        source = Snapshot::LifecycleSource.new(rows: [
          { id: 1, public_id: "d9-1", suspended_at: 2.days.ago, suspension_reason: "spam reports",
            discovery_restricted_at: 2.days.ago, discovery_restricted_by_id: 1 }
        ])
        result = LifecycleImport.call(brand: @brand, source:)
        assert_equal 1, result.reconciliation.count(:moderation_state, :imported)

        record = Date9jaHistoryRecord.find_by!(source_entity: "moderation_state", source_id: "1")
        assert_equal @retained.user, record.user
        assert_equal "suspended", record.status
        assert_equal true, record.payload["restricting_actor_present"]
      end

      private

      def profile(name, gender)
        user = User.create!
        membership = BrandMembership.create!(brand: @brand, user:)
        Profile.create!(brand: @brand, user:, brand_membership: membership,
          display_name: name, birthdate: 30.years.ago.to_date, gender:)
      end
    end
  end
end
