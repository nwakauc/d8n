module Ai
  module Context
    module Date9ja
      INTRODUCTION_SURFACE = "discovery.curated_daily".freeze

      def self.call(user:, brand:, membership:)
        viewer = Profile.kept.find_by(user:, brand:, brand_membership: membership)
        return { "product" => "Date9ja", "introductions" => [] } unless viewer

        {
          "product" => "Date9ja",
          "member_profile" => profile_summary(viewer),
          "member_preferences" => preference_summary(viewer.profile_preference),
          "introductions" => introductions(brand:, membership:, viewer:)
        }
      end

      def self.introductions(brand:, membership:, viewer:)
        allocation = DiscoveryAllocation.kept.find_by(
          brand:, brand_membership: membership, surface_key: INTRODUCTION_SURFACE,
          allocation_date: Time.current.in_time_zone("Africa/Lagos").to_date
        )
        return [] unless allocation

        surface = D8n::Platform::BrandRegistry.fetch(brand:).surface(INTRODUCTION_SURFACE)
        visible_ids = Matching::ExclusionsScope.call(
          scope: Matching::EligibilityScope.call(brand:, viewer:, policy: surface.eligibility_policy),
          viewer:, contributors: surface.exclusions
        ).where(id: allocation.allocation_candidates.kept.select(:candidate_profile_id)).pluck(:id).to_set

        allocation.allocation_candidates.kept.order(:position).includes(candidate_profile: [
          :profile_preference,
          { profile_option_selections: [ :profile_option, :profile_option_group ] }
        ]).filter_map do |item|
          candidate = item.candidate_profile
          next unless candidate && visible_ids.include?(candidate.id)

          profile_summary(candidate).merge(
            "introduction_position" => item.position,
            "compatibility" => item.ranking_payload.fetch("compatibility", {})
          )
        end
      end
      private_class_method :introductions

      def self.profile_summary(profile)
        # This intentionally reuses the public-profile boundary, then removes
        # media URLs: the provider receives no images, video URLs, or storage data.
        Profiles::PublicSerializer.call(profile:).except(:photos)
      end
      private_class_method :profile_summary

      def self.preference_summary(preference)
        return {} unless preference

        preference.slice(:relationship_intent, :interested_in, :min_age, :max_age, :preferred_country_codes)
      end
      private_class_method :preference_summary
    end
  end
end
