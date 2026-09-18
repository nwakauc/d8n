require "test_helper"

module Date9ja
  module Import
    class MembershipReferenceRepairTest < ActiveSupport::TestCase
      setup do
        @brand = Brand.create!(slug: "date9ja", name: "Date9ja")
        digest = BCrypt::Password.create("synthetic-password", cost: 4).to_s
        @source = Snapshot::UserSource.new(rows: (1..2).map do |id|
          { id:, email: "repair#{id}@example.com", encrypted_password: digest, created_at: "2023-01-01" }
        end)
        IdentityImport.call(brand: @brand, source: @source)
        @first = Migration::ReferenceMap.resolve(source_system: "date9ja", source_entity: "membership", source_id: "1")
        @target = @first.destination
        @first.update_columns(destination_id: BrandMembership.maximum(:id) + 1000)
      end

      test "explicit correction plan repairs mappings only and reruns with zero corrections" do
        before = [ User, IdentityIdentifier, Credential, BrandMembership, Profile ].map(&:count)
        plan = MembershipReferenceRepair.plan(brand: @brand, source: @source)
        assert_equal 1, plan.size
        result = MembershipReferenceRepair.apply!(brand: @brand, source: @source, expected_plan: plan)
        assert_equal 1, result.fetch("membership_bindings.corrected")
        assert_equal @target, Migration::ReferenceMap.resolved(source_system: "date9ja", source_entity: "membership", source_id: "1")
        assert_equal before, [ User, IdentityIdentifier, Credential, BrandMembership, Profile ].map(&:count)
        assert_empty MembershipReferenceRepair.plan(brand: @brand, source: @source)
      end

      test "stale plan and production application cannot alter mappings" do
        assert_raises(ReferenceRepair::Conflict) do
          MembershipReferenceRepair.apply!(brand: @brand, source: @source, expected_plan: [])
        end
        plan = MembershipReferenceRepair.plan(brand: @brand, source: @source)
        stub_method(Rails.env, :production?, -> { true }) do
          assert_raises(ReferenceRepair::Conflict) do
            MembershipReferenceRepair.apply!(brand: @brand, source: @source, expected_plan: plan)
          end
        end
        assert_equal @first.destination_id, @first.reload.destination_id
      end
    end
  end
end
