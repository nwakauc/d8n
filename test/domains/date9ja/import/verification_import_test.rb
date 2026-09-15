require "test_helper"

module Date9ja
  module Import
    # Regression coverage for the Date9ja production dress rehearsal
    # (2026-09-15) findings against backups_db_production_20260915030000.dump:
    # this importer had no test coverage at all before that pass and two real
    # defects were found against the real corpus, not synthetic fixtures.
    class VerificationImportTest < ActiveSupport::TestCase
      setup do
        @brand = Brand.create!(slug: "date9ja", name: "Date9ja")
        @alice = profile("alice", "woman")
        bind(:user, "1", @alice.user)
      end

      # `evidence` is a real ActiveStorage has_one_attached column on
      # VerificationAssertion. Forcing `{}` into it (the pre-fix behaviour)
      # raised ArgumentError: missing keywords: :io, :filename -- reproduced
      # against the real production dump's verification_checks rows, which
      # never carry an `evidence` key at all (not selected).
      test "does not crash on rows with no evidence key (the real source shape)" do
        checks = [
          { id: 100, user_id: 1, check_type: "selfie", status: "approved", submitted_at: 2.days.ago, reviewed_at: 1.day.ago }
        ]

        result = VerificationImport.call(brand: @brand, checks:)

        assert_equal 1, result.imported
        assert_equal 0, result.failed
        assertion = VerificationAssertion.find_by!(brand: @brand, source_type: "verification_check", source_id: "100")
        assert_equal "selfie", assertion.check_type
        assert_equal "approved", assertion.status
        refute assertion.evidence.attached?
      end

      # `verification_events` is a transition audit log on verification_checks
      # (verification_check_id, event_type, metadata) -- it has no `kind` or
      # `status` column. Treating it as an independent assertion source (a
      # prior version of this importer did) produced check_type:
      # "verification_event" / status: "unknown" rows invisible to
      # RealmeBadge/InteractionAccess. It is no longer a VerificationImport
      # input at all -- `.call` doesn't accept an `events:` keyword.
      test "does not accept an events: source (verification_events is not an independent check)" do
        assert_raises(ArgumentError) do
          VerificationImport.call(brand: @brand, checks: [], events: [ { id: 1 } ])
        end
      end

      # selfie_verifications carries no check_type column (the whole table is
      # selfie checks) and its `status` is a plain integer ordinal (0/1/2),
      # not a string enum like verification_checks.status. The real production
      # corpus never held 0 (pending); 1 (the overwhelming majority) is
      # approved, 2 (a single outlier) is rejected.
      test "decodes legacy selfie_verifications rows to check_type selfie with the correct status" do
        selfies = [
          { id: 200, user_id: 1, status: "1", reviewed_at: 1.day.ago },
          { id: 201, user_id: 1, status: "2", reviewed_at: 1.day.ago }
        ]

        result = VerificationImport.call(brand: @brand, checks: [], selfies:)

        assert_equal 2, result.imported
        assert_equal 0, result.failed
        approved = VerificationAssertion.find_by!(brand: @brand, source_type: "selfie_verification", source_id: "200")
        rejected = VerificationAssertion.find_by!(brand: @brand, source_type: "selfie_verification", source_id: "201")
        assert_equal "selfie", approved.check_type
        assert_equal "approved", approved.status
        assert_equal "selfie", rejected.check_type
        assert_equal "rejected", rejected.status
      end

      # An unrecognised status ordinal must fail closed to "pending" -- never
      # "approved". A wrong guess here is security-relevant (RealMe messaging
      # gate / badge eligibility), so an out-of-range or non-numeric status
      # must never silently become a qualifying state.
      test "an unrecognised selfie status ordinal fails closed to pending, never approved" do
        selfies = [
          { id: 202, user_id: 1, status: "99", reviewed_at: 1.day.ago },
          { id: 203, user_id: 1, status: nil, reviewed_at: 1.day.ago }
        ]

        result = VerificationImport.call(brand: @brand, checks: [], selfies:)

        assert_equal 2, result.imported
        VerificationAssertion.where(brand: @brand, source_type: "selfie_verification").find_each do |assertion|
          assert_equal "pending", assertion.status
        end
      end

      test "a check_type-qualifying selfie satisfies the InteractionAccess messaging gate" do
        VerificationImport.call(brand: @brand, checks: [], selfies: [
          { id: 204, user_id: 1, status: "1", reviewed_at: 1.day.ago }
        ])

        assert VerificationAssertion.exists?(brand: @brand, user: @alice.user, check_type: "selfie", status: "approved")
      end

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
