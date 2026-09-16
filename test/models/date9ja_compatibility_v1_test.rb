require "test_helper"

module Matching
  module Strategies
    class Date9jaCompatibilityV1Test < ActiveSupport::TestCase
      setup do
        @brand = Brand.create!(slug: "date9ja", name: "Date9ja")
        Profiles::Date9jaProfileCatalog.install!(brand: @brand)
        @viewer = create_profile(gender: "woman", interested_in: [ "man" ])
        @candidate = create_profile(gender: "man", interested_in: [ "woman" ])
      end

      test "is deterministic symmetric and versioned" do
        apply_relationship_answers(@viewer)
        apply_relationship_answers(@candidate)
        set_genotype(@viewer, "aa")
        set_genotype(@candidate, "as")

        first = Date9jaContract.call(brand: @brand, viewer: @viewer, candidate: @candidate)
        repeated = Date9jaContract.call(brand: @brand, viewer: @viewer, candidate: @candidate)
        reversed = Date9jaContract.call(brand: @brand, viewer: @candidate, candidate: @viewer)

        assert_equal first, repeated
        assert_equal first, reversed
        assert_equal "date9ja_v1", first.version
        assert_equal 100, first.score
        assert_equal "no_elevated_risk_identified",
          first.critical_checks.dig(:hemoglobin_genotype, :status)
      end

      test "missing not tested and prefer not to say genotypes pass through as not assessed" do
        [ nil, "not_tested", "prefer_not_to_say" ].each do |candidate_genotype|
          set_genotype(@viewer, "as")
          set_genotype(@candidate, candidate_genotype) if candidate_genotype

          result = Date9jaContract.for_visible_pair(brand: @brand, viewer: @viewer, candidate: @candidate)

          assert_equal "not_assessed", result.critical_checks.dig(:hemoglobin_genotype, :status)
          assert_equal "incomplete", result.critical_checks.dig(:hemoglobin_genotype, :evidence_level)
          clear_genotype(@candidate)
        end
      end

      test "calculates AS and AS as a 25 percent sickle cell disease risk" do
        set_genotype(@viewer, "as")
        set_genotype(@candidate, "as")

        check = Date9jaContract.for_visible_pair(
          brand: @brand, viewer: @viewer, candidate: @candidate
        ).critical_checks.fetch(:hemoglobin_genotype)

        assert_equal "elevated_sickle_cell_risk", check.fetch(:status)
        assert_equal 0.25, check.fetch(:sickle_cell_disease_probability)
      end

      test "calculates AS and AC as a 25 percent HbSC risk" do
        set_genotype(@viewer, "as")
        set_genotype(@candidate, "ac")

        check = Date9jaContract.for_visible_pair(
          brand: @brand, viewer: @viewer, candidate: @candidate
        ).critical_checks.fetch(:hemoglobin_genotype)

        assert_equal "elevated_sickle_cell_risk", check.fetch(:status)
        assert_equal 0.25, check.fetch(:sickle_cell_disease_probability)
      end

      test "calculates AC and AC as a separately named 25 percent HbCC risk" do
        set_genotype(@viewer, "ac")
        set_genotype(@candidate, "ac")

        result = Date9jaContract.for_visible_pair(
          brand: @brand, viewer: @viewer, candidate: @candidate
        )
        check = result.critical_checks.fetch(:hemoglobin_genotype)

        assert result.blocking_inherited_risk?
        assert_equal "other_hemoglobin_risk", check.fetch(:status)
        assert_equal 0.25, check.fetch(:other_hemoglobin_disease_probability)
      end

      test "unknown genotype does not block daily introductions but elevated known risk does" do
        safe = create_profile(gender: "man", interested_in: [ "woman" ])
        risky = create_profile(gender: "man", interested_in: [ "woman" ])
        set_genotype(@viewer, "as")
        set_genotype(risky, "as")

        ranked = Date9jaContract.rank_daily_selection(
          scope: @brand.profiles.where(id: [ safe.id, risky.id ]), viewer: @viewer,
          eligibility_policy: D8n::Platform::Brands::Date9ja::ELIGIBILITY_POLICY, limit: 10
        )

        assert_equal [ safe.id ], ranked.pluck(:profile).pluck(:id)
        assert_equal "not_assessed",
          ranked.sole.dig(:ranking_payload, :compatibility, :critical_checks, :hemoglobin_genotype, :status)
      end

      test "withholds a percentage below the meaningful comparison threshold without hiding genotype status" do
        set_genotype(@viewer, "aa")
        set_genotype(@candidate, "as")

        result = Date9jaContract.for_visible_pair(brand: @brand, viewer: @viewer, candidate: @candidate)

        assert_nil result.score
        assert_empty result.reasons
        assert_equal "no_elevated_risk_identified",
          result.public_payload.dig(:critical_checks, :hemoglobin_genotype, :status)
      end

      test "rejects a cross brand pair neutrally" do
        other_brand = Brand.create!(slug: "other", name: "Other")
        other = create_profile(brand: other_brand, gender: "man", interested_in: [ "woman" ])

        assert_raises(Date9jaContract::IneligiblePair) do
          Date9jaContract.for_visible_pair(brand: @brand, viewer: @viewer, candidate: other)
        end
      end

      private

      def apply_relationship_answers(profile)
        profile.update!(country_code: "NG")
        Profiles::OptionSelections.replace!(profile:, selections: {
          religion: [ "christian" ], tribe: [ "igbo" ], relationship_intent: [ "marriage" ],
          commitment_timeline: [ "within_1_year" ], wants_children: [ "yes" ],
          faith_practice: [ "practice_regularly" ], money_providing: [ "joint_and_personal" ],
          conflict: [ "cool_off_first" ]
        })
        keep_discoverable!(profile)
      end

      def set_genotype(profile, code)
        Profiles::OptionSelections.replace!(profile:, selections: { genotype: [ code ] })
        keep_discoverable!(profile)
      end

      def clear_genotype(profile)
        Profiles::OptionSelections.replace!(profile:, selections: { genotype: [] })
        keep_discoverable!(profile)
      end

      def keep_discoverable!(profile)
        profile.update!(status: :active, visibility: :visible)
      end

      def create_profile(brand: @brand, gender:, interested_in:)
        user = User.create!
        membership = BrandMembership.create!(brand:, user:)
        profile = Profile.create!(
          brand:, user:, brand_membership: membership, gender:, birthdate: 30.years.ago.to_date,
          status: :active, visibility: :visible
        )
        ProfilePreference.create!(brand:, user:, profile:, interested_in:)
        profile
      end
    end
  end
end
