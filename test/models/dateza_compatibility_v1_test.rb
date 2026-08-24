require "test_helper"

module Matching
  module Strategies
    class DatezaV1Test < ActiveSupport::TestCase
      setup do
        @brand = Brand.create!(slug: "dateza", name: "DateZA")
        Profiles::DatezaProfileCatalog.install!(brand: @brand)
        @viewer = create_profile(gender: "woman", interested_in: [ "man" ])
        @candidate = create_profile(gender: "man", interested_in: [ "woman" ])
      end

      test "is deterministic symmetric and explicitly versioned" do
        apply_high_agreement

        first = DatezaV1.call(brand: @brand, viewer: @viewer, candidate: @candidate)
        repeated = DatezaV1.call(brand: @brand, viewer: @viewer, candidate: @candidate)
        reversed = DatezaV1.call(brand: @brand, viewer: @candidate, candidate: @viewer)

        assert_equal first, repeated
        assert_equal first, reversed
        assert_not_includes Profile.column_names, "compatibility_score"
        assert_equal "dateza_v1", first.version
        assert_equal "high", first.confidence_level
        assert_in_delta 1.0, first.confidence
        assert_equal 100, first.score
      end

      test "relationship and family conflict outweigh trivial shared interests" do
        set_values(@viewer, relationship_intent: "long_term_relationship", has_children: "no", wants_children: "yes",
          interests: %w[coffee movies travel], smoking: "never", drinking: "occasionally")
        set_values(@candidate, relationship_intent: "friendship", has_children: "no", wants_children: "no",
          interests: %w[coffee movies travel], smoking: "never", drinking: "occasionally")

        conflicting = DatezaV1.call(brand: @brand, viewer: @viewer, candidate: @candidate)

        set_values(@candidate, relationship_intent: "long_term_relationship", has_children: "no", wants_children: "yes",
          interests: %w[rugby reading], smoking: "never", drinking: "occasionally")
        aligned = DatezaV1.call(brand: @brand, viewer: @viewer, candidate: @candidate)

        assert_equal 46, conflicting.score
        assert_equal 94, aligned.score
        assert_in_delta 0.69, conflicting.confidence
        assert_operator aligned.score, :>, conflicting.score + 30
        assert_includes conflicting.reasons, "relationship_goal_mismatch"
        assert_includes conflicting.reasons, "family_plan_mismatch"
        assert_includes conflicting.reasons, "shared_interests"
      end

      test "withholds a score and reasons below the meaningful-data minimum" do
        set_values(@viewer, relationship_intent: "long_term_relationship")
        set_values(@candidate, relationship_intent: "long_term_relationship")

        result = DatezaV1.call(brand: @brand, viewer: @viewer, candidate: @candidate)

        assert_nil result.score
        assert_nil result.public_payload
        assert_equal "low", result.confidence_level
        assert_in_delta 0.2, result.confidence
        assert_empty result.reasons
      end

      test "reports medium confidence from meaningful but partial comparable data" do
        values = { relationship_intent: "marriage", has_children: "no", wants_children: "yes" }
        set_values(@viewer, **values)
        set_values(@candidate, **values)

        result = DatezaV1.call(brand: @brand, viewer: @viewer, candidate: @candidate)

        assert_equal 100, result.score
        assert_in_delta 0.5, result.confidence
        assert_equal "medium", result.confidence_level
      end

      test "emits only bounded privacy-safe reason codes" do
        apply_high_agreement
        result = DatezaV1.call(brand: @brand, viewer: @viewer, candidate: @candidate)
        serialized = result.public_payload.to_json

        assert_empty result.reasons - DatezaV1::EXPLANATION_CODES
        assert result.reasons.size <= DatezaV1::MAX_REASONS
        assert_not_includes serialized, "very_important"
        assert_not_includes serialized, "yes"
        assert_not_includes serialized, "latitude"
        assert_not_includes serialized, "longitude"
        assert_not_includes serialized, "trust"
        assert_not_includes serialized, "risk"
      end

      test "does not use popularity Trust RealMe activity or location as score inputs" do
        apply_high_agreement
        before = DatezaV1.call(brand: @brand, viewer: @viewer, candidate: @candidate)

        admirer = create_profile(gender: "person", interested_in: [ "person" ])
        Like.create!(brand: @brand, liker_profile: admirer, liked_profile: @candidate)
        first_id, second_id = Match.canonical_pair(admirer.id, @candidate.id)
        Match.create!(brand: @brand, profile_a_id: first_id, profile_b_id: second_id)
        @candidate.update_columns(updated_at: 5.minutes.ago)

        after = DatezaV1.call(brand: @brand, viewer: @viewer, candidate: @candidate)

        assert_equal before, after
        assert_empty DatezaV1::WEIGHTS.keys & %i[
          popularity likes matches trust risk realme verification activity distance exact_location
        ]
      end

      test "fails neutrally for cross-brand HookUs and bilaterally ineligible pairs" do
        hookus = Brand.create!(slug: "hookus", name: "HookUs")
        hookus_candidate = create_profile(brand: hookus, gender: "man", interested_in: [ "woman" ])

        assert_raises(DatezaV1::IneligiblePair) do
          DatezaV1.call(brand: @brand, viewer: @viewer, candidate: hookus_candidate)
        end
        assert_raises(StrategyRegistry::UnsupportedBrand) { StrategyRegistry.compatibility_for(brand: hookus) }
        assert_equal Strategies::Hookus, StrategyRegistry.fetch(brand: hookus)

        @candidate.profile_preference.update!(min_age: 40)
        assert_raises(DatezaV1::IneligiblePair) do
          DatezaV1.call(brand: @brand, viewer: @viewer, candidate: @candidate)
        end
      end

      test "registers compatibility and the configured DateZA daily Discovery ranking" do
        assert_equal DatezaV1, StrategyRegistry.compatibility_for(brand: @brand)
        assert_equal DatezaV1, StrategyRegistry.fetch(brand: @brand)
        assert_equal :daily_batch, StrategyRegistry.fetch_surface(brand: @brand).delivery_type
      end

      private

      def apply_high_agreement
        values = {
          relationship_intent: "long_term_relationship", has_children: "no", wants_children: "yes",
          religion_importance: "somewhat_important", social_style: "ambivert", meeting_pace: "few_days",
          interests: %w[coffee travel reading], communication_style: "mixed", planning_style: "mix_of_both",
          travel_frequency: "sometimes", diet: "anything", smoking: "never", drinking: "occasionally",
          languages: %w[en zu]
        }
        set_values(@viewer, **values)
        set_values(@candidate, **values)
      end

      def set_values(profile, smoking: nil, drinking: nil, languages: nil, **selections)
        profile.update!(
          smoking: smoking || profile.smoking,
          drinking: drinking || profile.drinking,
          languages: languages&.map { |code| { code:, proficiency: "fluent" } } || profile.languages
        )
        Profiles::OptionSelections.replace!(
          profile:,
          selections: selections.transform_values { |value| Array(value) }
        ) if selections.any?
        profile.update!(status: :active, visibility: :visible)
      end

      def create_profile(brand: @brand, gender:, interested_in:)
        user = User.create!
        membership = BrandMembership.create!(brand:, user:)
        profile = Profile.create!(
          brand:, user:, brand_membership: membership, gender:, birthdate: 30.years.ago.to_date,
          status: :active, visibility: :visible
        )
        ProfilePreference.create!(
          brand:, user:, profile:, interested_in:, min_age: 18, max_age: 60
        )
        profile
      end
    end
  end
end
