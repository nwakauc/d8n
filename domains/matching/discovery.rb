module Matching
  class Discovery
    DEFAULT_LIMIT = 20
    MAX_LIMIT = 50

    class ViewerIneligible < StandardError; end
    class InvalidLimit < StandardError; end

    Result = Data.define(:profiles, :next_cursor, :strategy, :viewer)

    def self.call(user:, brand:, cursor: nil, limit: nil, mode: nil, vibe: nil, online: nil, restrict: nil, guard: nil)
      new(user:, brand:, cursor:, limit:, mode:, vibe:, online:, restrict:, guard:).call
    end

    def initialize(user:, brand:, cursor:, limit:, mode: nil, vibe: nil, online: nil, restrict: nil, guard: nil)
      @user = user
      @brand = brand
      @cursor = cursor
      @limit = normalize_limit(limit)
      @mode = mode
      @vibe = vibe
      @online = online
      @restrict = restrict
      @guard = guard
    end

    def call
      viewer = current_viewer!
      # Optional caller-supplied authorization on the resolved viewer, run AFTER
      # base eligibility so a non-discoverable viewer still fails with the usual
      # ViewerIneligible rather than a surface-specific reason. Any exception it
      # raises propagates to the caller (e.g. Hook Tonight's "must be in the pool
      # to view the pool").
      guard&.call(viewer)
      strategy = StrategyRegistry.fetch(brand:, mode:)
      filter = FacetFilter.parse(brand:, vibe:, online:)
      scope = EligibilityScope.call(brand:, viewer:, location_max_age: strategy.location_max_age)
      # Optional caller-supplied narrowing (e.g. Hook Tonight's "only members live
      # in the availability pool"). Applied on top of the shared eligible
      # population so an alternate surface reuses this one discovery engine rather
      # than forking it; it can only remove candidates, never relax eligibility.
      scope = restrict.call(scope, viewer) if restrict
      scope = ExclusionsScope.call(scope:, viewer:)
      scope = FacetFilter.apply(scope:, brand:, filter:)
      scope = strategy.rank(scope:, viewer:)
      scope = Cursor.apply(scope:, value: cursor, brand:, strategy:, filter:)
      profiles = scope.includes(
        { profile_option_selections: [ :profile_option, :profile_option_group ] },
        { profile_photos: { display_image_attachment: :blob } }
      ).limit(limit + 1).to_a
      has_more = profiles.length > limit
      profiles = profiles.first(limit)

      Result.new(
        profiles:,
        next_cursor: has_more ? Cursor.encode(brand:, strategy:, profile: profiles.last, filter:) : nil,
        strategy:,
        viewer:
      )
    end

    private

    attr_reader :user, :brand, :cursor, :limit, :mode, :vibe, :online, :restrict, :guard

    def current_viewer!
      profile = Profile.kept.find_by(user:, brand:)
      preference = ProfilePreference.kept.find_by(profile:) if profile
      eligible = profile&.active? && profile.visible? && profile.birthdate.present? && profile.gender.present? &&
        user.active? && user.deleted_at.nil? && profile.brand_membership.active? && profile.brand_membership.deleted_at.nil? &&
        preference&.deleted_at.nil? && preference.min_age.present? && preference.max_age.present? && preference.interested_in.any?
      eligible &&= profile.birthdate <= Profile::MINIMUM_AGE.years.ago.to_date

      raise ViewerIneligible, "an active discoverable profile is required" unless eligible

      profile
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
