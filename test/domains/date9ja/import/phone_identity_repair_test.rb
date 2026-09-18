require "test_helper"

module Date9ja
  module Import
    class PhoneIdentityRepairTest < ActiveSupport::TestCase
      setup do
        @brand = Brand.create!(slug: "date9ja", name: "Date9ja")
        @other = Brand.create!(slug: "dateza", name: "DateZA")
        @other_user = User.create!
        @other_phone = IdentityIdentifier.create!(brand: @other, user: @other_user, kind: :phone, normalized_value: "2348030000001")
        raw = { id: 1, email: "synthetic@example.com", phone: "+2348030000001", phone_verified_at: "2024-01-01",
          encrypted_password: BCrypt::Password.create("synthetic-password", cost: 4).to_s, created_at: "2023-01-01" }
        @source = Snapshot::UserSource.new(rows: [ raw ])
        IdentityImport.call(brand: @brand, source: @source)
        # Reproduce an earlier import that omitted a globally colliding phone.
        LegacyReference.for_source("date9ja").where(source_entity: "identity_phone").delete_all
        IdentityIdentifier.where(brand: @brand, kind: :phone).delete_all
      end

      test "restore omitted phone with new scoped ID and no cross-brand account merge" do
        unchanged = [ @other_user, @other_phone ].map(&:attributes)
        domain_counts = [ User, BrandMembership, Profile, Credential ].map(&:count)
        plan = PhoneIdentityRepair.plan(brand: @brand, source: @source)
        assert_equal 1, plan.size
        assert_difference -> { IdentityIdentifier.count }, 1 do
          PhoneIdentityRepair.apply!(brand: @brand, source: @source, expected_plan: plan)
        end
        phone = Migration::ReferenceMap.resolved(source_system: "date9ja", source_entity: "identity_phone", source_id: "1")
        assert_equal @brand, phone.brand
        assert phone.verified_at
        refute_equal @other_phone.id, phone.id
        refute_equal @other_user.id, phone.user_id
        assert_equal domain_counts, [ User, BrandMembership, Profile, Credential ].map(&:count)
        assert_equal unchanged, [ @other_user, @other_phone ].map { |record| record.reload.attributes }
        assert_empty PhoneIdentityRepair.plan(brand: @brand, source: @source)
        assert_equal 0, PhoneIdentityRepair.apply!(brand: @brand, source: @source, expected_plan: []).fetch("phone_identities.created")
      end

      test "an existing native phone prevents implicit baseline restoration" do
        user = Migration::ReferenceMap.resolved(source_system: "date9ja", source_entity: "user", source_id: "1")
        IdentityIdentifier.create!(brand: @brand, user:, kind: :phone, normalized_value: "2348030000002")
        assert_raises(ReferenceRepair::Conflict) { PhoneIdentityRepair.plan(brand: @brand, source: @source) }
      end
    end
  end
end
