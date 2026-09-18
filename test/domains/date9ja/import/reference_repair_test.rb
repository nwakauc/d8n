require "test_helper"

module Date9ja
  module Import
    class ReferenceRepairTest < ActiveSupport::TestCase
      setup do
        @brand = Brand.create!(slug: "date9ja", name: "Date9ja")
        @digest = BCrypt::Password.create("synthetic-password", cost: 4).to_s
      end

      def rows(count)
        (1..count).map do |id|
          { id:, email: "repair#{id}@example.com", phone: "+234#{8030000000 + id}",
            encrypted_password: @digest, created_at: "2023-01-01", confirmed_at: "2024-01-01",
            phone_verified_at: "2024-01-01", display_name: "Synthetic" }
        end
      end

      test "887-member promoted cohort repairs 885 missing user spines without mutating other brands" do
        raw = rows(887)
        source = Snapshot::UserSource.new(rows: raw)
        result = IdentityImport.call(brand: @brand, source:)
        assert_equal 887, result.reconciliation.count(:imported)
        other = Brand.create!(slug: "hookus", name: "HookUs")
        user = User.create!
        membership = BrandMembership.create!(brand: other, user:)
        profile = Profile.create!(brand: other, user:, brand_membership: membership)
        unrelated = [ user, membership, profile ].map(&:attributes)
        LegacyReference.for_source("date9ja").where(brand_id: nil).where.not(source_id: %w[1 2]).delete_all
        before = [ User, IdentityIdentifier, Credential, BrandMembership, Profile ].map(&:count)
        preview = ReferenceRepair.call(brand: @brand, source:)
        assert_equal 887, preview.fetch("user.reconciled")
        assert_equal 885, preview.fetch("user.missing")
        ReferenceRepair.call(brand: @brand, source:, apply: true)
        %w[user identity_email identity_phone password_credential].each do |entity|
          refs = LegacyReference.for_source("date9ja").where(source_entity: entity)
          assert_equal 887, refs.count
          assert_equal 0, refs.where.not(brand_id: nil).count
          assert_equal 887, refs.distinct.count(:destination_id)
        end
        assert_equal before, [ User, IdentityIdentifier, Credential, BrandMembership, Profile ].map(&:count)
        refs_before = LegacyReference.count
        second = ReferenceRepair.call(brand: @brand, source:, apply: true)
        assert_equal 0, second.fetch("user.missing", 0)
        assert_equal refs_before, LegacyReference.count
        assert_equal unrelated, [ user, membership, profile ].map { |record| record.reload.attributes }
      end

      test "a source phone collision remains excluded rather than merging identities" do
        raw = rows(2)
        raw.last[:phone] = raw.first[:phone]
        source = Snapshot::UserSource.new(rows: raw)
        IdentityImport.call(brand: @brand, source:)
        before = IdentityIdentifier.count
        counts = ReferenceRepair.call(brand: @brand, source:, apply: true)
        assert_equal 1, counts.fetch("identity_phone.reconciled")
        assert_equal 1, counts.fetch("phone_collision_excluded")
        assert_equal before, IdentityIdentifier.count
        assert_equal 2, LegacyReference.for_source("date9ja").where(source_entity: "user").count
      end

      test "wrong baseline email aborts all reconstruction without identity merging" do
        raw = rows(2)
        source = Snapshot::UserSource.new(rows: raw)
        IdentityImport.call(brand: @brand, source:)
        LegacyReference.for_source("date9ja").where(brand_id: nil).delete_all
        raw.last[:email] = raw.first[:email]
        assert_no_difference -> { LegacyReference.count } do
          assert_raises(ReferenceRepair::Conflict) do
            ReferenceRepair.call(brand: @brand, source: Snapshot::UserSource.new(rows: raw), apply: true)
          end
        end
      end
    end
  end
end
