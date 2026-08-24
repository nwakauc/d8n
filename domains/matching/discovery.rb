module Matching
  class Discovery
    DEFAULT_LIMIT = 20
    MAX_LIMIT = 50

    class ViewerIneligible < StandardError; end
    class InvalidLimit < StandardError; end

    Result = Data.define(
      :profiles, :next_cursor, :strategy, :viewer, :eligibility_policy, :decorators,
      :compatibility_by_profile, :selection
    )

    def self.call(user:, brand:, cursor: nil, limit: nil, mode: nil, facet_params: {}, restrict: nil, guard: nil,
      surface: nil, now: Time.current)
      new(user:, brand:, cursor:, limit:, mode:, facet_params:, restrict:, guard:, surface:, now:).call
    end

    def initialize(user:, brand:, cursor:, limit:, mode: nil, facet_params: {}, restrict: nil, guard: nil,
      surface: nil, now:)
      @user = user
      @brand = brand
      @cursor = cursor
      @limit = normalize_limit(limit)
      @mode = mode
      @facet_params = facet_params
      @restrict = restrict
      @guard = guard
      @surface = surface
      @now = now
    end

    def call
      selected_surface = surface || StrategyRegistry.fetch_surface(brand:, mode:)
      if selected_surface.delivery_type == :daily_batch
        raise Cursor::Invalid, "daily batch selections are not cursor-paginated" if cursor.present?

        return daily_selection_result(selected_surface)
      end

      viewer = current_viewer!
      # Optional caller-supplied authorization on the resolved viewer, run AFTER
      # base eligibility so a non-discoverable viewer still fails with the usual
      # ViewerIneligible rather than a surface-specific reason. Any exception it
      # raises propagates to the caller (e.g. Hook Tonight's "must be in the pool
      # to view the pool").
      guard&.call(viewer)
      strategy = selected_surface.strategy
      filter = FacetFilter.parse(brand:, definitions: selected_surface.facets, params: facet_params)
      scope = EligibilityScope.call(brand:, viewer:, policy: selected_surface.eligibility_policy)
      # Optional caller-supplied narrowing (e.g. Hook Tonight's "only members live
      # in the availability pool"). Applied on top of the shared eligible
      # population so an alternate surface reuses this one discovery engine rather
      # than forking it; it can only remove candidates, never relax eligibility.
      scope = restrict.call(scope, viewer) if restrict
      scope = ExclusionsScope.call(scope:, viewer:, contributors: selected_surface.exclusions)
      scope = FacetFilter.apply(scope:, brand:, filter:)
      scope = strategy.rank(scope:, viewer:, eligibility_policy: selected_surface.eligibility_policy)
      scope = Cursor.apply(scope:, value: cursor, brand:, strategy:, filter:)
      profiles = scope.includes(
        :brand,
        { profile_option_selections: [ :profile_option, :profile_option_group ] },
        { profile_photos: { display_image_attachment: :blob } }
      ).limit(limit + 1).to_a
      has_more = profiles.length > limit
      profiles = profiles.first(limit)

      Result.new(
        profiles:,
        next_cursor: has_more ? Cursor.encode(brand:, strategy:, profile: profiles.last, filter:) : nil,
        strategy:,
        viewer:,
        eligibility_policy: selected_surface.eligibility_policy,
        decorators: selected_surface.decorators,
        compatibility_by_profile: nil,
        selection: nil
      )
    end

    private

    attr_reader :user, :brand, :cursor, :limit, :mode, :facet_params, :restrict, :guard, :surface, :now

    def daily_selection_result(selected_surface)
      FacetFilter.parse(brand:, definitions: selected_surface.facets, params: facet_params)
      daily = StableDailySelection.call(user:, brand:, surface: selected_surface, now:)
      Result.new(
        profiles: daily.profiles,
        next_cursor: nil,
        strategy: selected_surface.strategy,
        viewer: daily.viewer,
        eligibility_policy: daily.eligibility_policy,
        decorators: daily.decorators,
        compatibility_by_profile: daily.compatibility_by_profile,
        selection: daily.selection
      )
    rescue StableDailySelection::ViewerIneligible
      raise ViewerIneligible, "an active discoverable profile is required"
    end

    def current_viewer!
      ProfileParticipant.discoverable!(user:, brand:)
    rescue InteractionError
      raise ViewerIneligible, "an active discoverable profile is required"
    end

    def normalize_limit(value)
      return DEFAULT_LIMIT if value.blank?

      parsed = Integer(value, 10)
      raise InvalidLimit, "limit must be between 1 and #{MAX_LIMIT}" unless parsed.between?(1, MAX_LIMIT)

      parsed
    rescue ArgumentError, TypeError
      raise InvalidLimit, "limit must be between 1 and #{MAX_LIMIT}"
    end
  end
end
