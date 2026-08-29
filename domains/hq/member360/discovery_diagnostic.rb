module Hq
  module Member360
    # Read-only "why is Discover empty for this member?" explain-mode wrapper
    # around the live discovery engine. Reuses Matching::VisibilityScope,
    # Matching::EligibilityScope, and Matching::ExclusionsScope verbatim --
    # it never reimplements filter logic, never mutates DiscoveryAllocation/
    # DiscoveryAllocationCandidate, and never consumes the member's normal
    # daily discovery quota. See ARCHITECTURE.md §6.
    #
    # Stage granularity is coarser than the product brief's ideal (gender/age/
    # distance as three separate counts): EligibilityScope applies those three
    # filters as one private, chained scope and does not expose intermediate
    # counts today. Splitting them further would mean either reimplementing
    # that logic here (explicitly disallowed) or changing EligibilityScope's
    # public interface, which is out of scope for this slice. Documented as a
    # known limitation, not silently worked around.
    class DiscoveryDiagnostic
      Result = Data.define(:eligible, :ineligibility_reason, :stages)
      Stage = Data.define(:stage, :description, :candidate_count)

      def self.call(brand:, profile:)
        new(brand:, profile:).call
      end

      def initialize(brand:, profile:)
        @brand = brand
        @profile = profile
      end

      def call
        viewer = eligible_viewer
        return ineligible_result if viewer.blank?

        surface = surface_for
        return not_configured_result if surface.blank?

        Result.new(eligible: true, ineligibility_reason: nil, stages: build_stages(viewer:, surface:))
      end

      private

      attr_reader :brand, :profile

      def eligible_viewer
        Matching::ProfileParticipant.discoverable!(user: profile.user, brand:)
      rescue Matching::InteractionError => e
        @ineligibility_reason = e.code.to_s
        nil
      end

      def ineligible_result
        Result.new(eligible: false, ineligibility_reason: @ineligibility_reason, stages: [])
      end

      def not_configured_result
        Result.new(eligible: false, ineligibility_reason: "discovery_not_configured", stages: [])
      end

      def surface_for
        Matching::StrategyRegistry.fetch_surface(brand:, mode: nil)
      rescue Matching::StrategyRegistry::UnsupportedBrand, Matching::StrategyRegistry::UnsupportedMode
        nil
      end

      def build_stages(viewer:, surface:)
        visibility = Matching::VisibilityScope.call(brand:, viewer:)
        eligibility = Matching::EligibilityScope.call(brand:, viewer:, policy: surface.eligibility_policy)
        excluded = Matching::ExclusionsScope.call(scope: eligibility, viewer:, contributors: surface.exclusions)

        [
          Stage.new(
            stage: "visible_active_profiles",
            description: "Brand-matched, active, visible profiles of minimum age, excluding blocks in either direction.",
            candidate_count: visibility.count
          ),
          Stage.new(
            stage: "reciprocal_gender_age_distance",
            description: "Of the above, profiles matching this member's and the candidate's mutual gender, age, and distance preferences.",
            candidate_count: eligibility.count
          ),
          Stage.new(
            stage: "final_eligible_candidates",
            description: "Of the above, excluding profiles already liked, passed, or matched by this member.",
            candidate_count: excluded.count
          )
        ]
      end
    end
  end
end
