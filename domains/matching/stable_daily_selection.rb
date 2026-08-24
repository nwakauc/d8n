module Matching
  class StableDailySelection
    class ViewerIneligible < StandardError; end

    Result = Data.define(
      :profiles, :viewer, :eligibility_policy, :decorators,
      :compatibility_by_profile, :selection
    )

    def self.call(user:, brand:, surface:, now: Time.current)
      new(user:, brand:, surface:, now:).call
    end

    def initialize(user:, brand:, surface:, now:)
      @user = user
      @brand = brand
      @surface = surface
      @policy = surface.allocation
      @now = now
    end

    def call
      membership = BrandMembership.kept.active.find_by(user:, brand:)
      raise ViewerIneligible if membership.blank?

      result = nil
      BrandMembership.transaction do
        membership.lock!
        viewer = current_viewer!
        allocation = find_or_create_allocation!(membership:, viewer:)
        result = deliver(allocation:, viewer:)
      end
      result
    end

    private

    attr_reader :user, :brand, :surface, :policy, :now

    def current_viewer!
      ProfileParticipant.discoverable!(user:, brand:)
    rescue InteractionError
      raise ViewerIneligible
    end

    def find_or_create_allocation!(membership:, viewer:)
      allocation_date = policy.date_at(now)
      allocation = DiscoveryAllocation.kept.find_by(
        brand:, brand_membership: membership, surface_key: surface.key.to_s, allocation_date:
      )
      return allocation if allocation

      ranked_candidates = surface.strategy.rank_daily_selection(
        scope: candidate_scope(viewer:),
        viewer:,
        eligibility_policy: surface.eligibility_policy,
        limit: policy.daily_limit
      )
      allocation = DiscoveryAllocation.create!(
        brand:, user:, brand_membership: membership, viewer_profile: viewer,
        surface_key: surface.key.to_s, allocation_date:, time_zone: policy.time_zone,
        daily_limit: policy.daily_limit, strategy_key: surface.strategy.key,
        policy_key: policy.key, finalized_at: now
      )
      ranked_candidates.each_with_index do |ranked, index|
        allocation.allocation_candidates.create!(
          brand:, candidate_profile: ranked.fetch(:profile), position: index + 1,
          ranking_payload: ranked.fetch(:ranking_payload)
        )
      end
      allocation
    end

    def candidate_scope(viewer:)
      scope = EligibilityScope.call(brand:, viewer:, policy: surface.eligibility_policy)
      ExclusionsScope.call(scope:, viewer:, contributors: surface.exclusions)
    end

    def deliver(allocation:, viewer:)
      items = allocation.allocation_candidates.kept.includes(
        candidate_profile: [
          :brand,
          { profile_option_selections: [ :profile_option, :profile_option_group ] },
          { profile_photos: { display_image_attachment: :blob } }
        ]
      ).to_a
      currently_eligible_ids = candidate_scope(viewer:)
        .where(id: items.map(&:candidate_profile_id))
        .pluck(:id)
        .to_set
      visible_items = items.select { |item| currently_eligible_ids.include?(item.candidate_profile_id) }
      profiles = visible_items.map(&:candidate_profile)

      Result.new(
        profiles:,
        viewer:,
        eligibility_policy: surface.eligibility_policy,
        decorators: surface.decorators,
        compatibility_by_profile: visible_items.to_h do |item|
          [ item.candidate_profile_id, item.ranking_payload["compatibility"] ]
        end,
        selection: {
          allocation_date: allocation.allocation_date.iso8601,
          daily_limit: allocation.daily_limit,
          count: profiles.size,
          finalized: true,
          refreshes_at: policy.resets_at(now).iso8601
        }
      )
    end
  end
end
