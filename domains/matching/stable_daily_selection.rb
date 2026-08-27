module Matching
  # DateZA's curated daily Discover surface: up to `daily_limit` distinct,
  # ranked candidates per member per day (`StableDailyAllocationPolicy`),
  # frozen at first request so the ORDER a member sees is stable across the
  # day, but never left to silently shrink toward zero as the member likes,
  # passes, or blocks their way through it.
  #
  # This is a completely separate allowance from Matching::Find::Search: a
  # distinct table (`DiscoveryAllocation`/`DiscoveryAllocationCandidate` vs
  # `FindProfileExposure`), a distinct daily counter, and this class never
  # reads or writes Find's ledger. Depleting today's Discover batch has no
  # effect on Find's own remaining allowance, and vice versa — the two
  # surfaces are independent by construction, not just by convention.
  class StableDailySelection
    class ViewerIneligible < StandardError; end

    Result = Data.define(
      :profiles, :viewer, :eligibility_policy, :decorators,
      :compatibility_by_profile, :selection
    )

    def self.call(user:, brand:, surface:, filter: FacetFilter::NONE, now: Time.current)
      new(user:, brand:, surface:, filter:, now:).call
    end

    def initialize(user:, brand:, surface:, filter:, now:)
      @user = user
      @brand = brand
      @surface = surface
      @policy = surface.allocation
      @filter = filter
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
        top_up!(allocation:, viewer:)
        result = deliver(allocation:, viewer:)
      end
      result
    end

    private

    attr_reader :user, :brand, :surface, :policy, :filter, :now

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
      append_candidates!(allocation:, ranked_candidates:, starting_position: 1)
      allocation
    end

    # Replenishes today's batch back up to `daily_limit` DISTINCT available
    # candidates, drawn from the same eligible pool the surface always used —
    # never from Find's separate candidate ledger. Without this, a member who
    # likes/passes/blocks their way through the initial batch would watch
    # Discover shrink toward zero over the course of the day even though
    # today's allotment (`daily_limit`) is nowhere near used up; the "stable"
    # part of stable-daily-selection is the RANKING/ORDER already-shown
    # candidates keep, not an artificial ceiling on how many distinct people a
    # member may see in one day.
    def top_up!(allocation:, viewer:)
      already_assigned_ids = allocation.allocation_candidates.pluck(:candidate_profile_id)
      live_count = candidate_scope(viewer:).where(id: already_assigned_ids).count
      needed = allocation.daily_limit - live_count
      return unless needed.positive?

      pool = candidate_scope(viewer:).where.not(id: already_assigned_ids)
      ranked_candidates = surface.strategy.rank_daily_selection(
        scope: pool, viewer:, eligibility_policy: surface.eligibility_policy, limit: needed
      )
      return if ranked_candidates.empty?

      next_position = allocation.allocation_candidates.maximum(:position).to_i + 1
      append_candidates!(allocation:, ranked_candidates:, starting_position: next_position)
    end

    def append_candidates!(allocation:, ranked_candidates:, starting_position:)
      ranked_candidates.each_with_index do |ranked, index|
        allocation.allocation_candidates.create!(
          brand:, candidate_profile: ranked.fetch(:profile), position: starting_position + index,
          ranking_payload: ranked.fetch(:ranking_payload)
        )
      end
    end

    def candidate_scope(viewer:)
      scope = EligibilityScope.call(brand:, viewer:, policy: surface.eligibility_policy)
      scope = ExclusionsScope.call(scope:, viewer:, contributors: surface.exclusions)
      FacetFilter.apply(scope:, brand:, filter:)
    end

    def deliver(allocation:, viewer:)
      items = allocation.allocation_candidates.kept.order(:position).includes(
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
