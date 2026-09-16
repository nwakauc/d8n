module Matching
  # Brand-specific discovery policy: the knobs a brand turns on the one shared
  # D8N matching engine. Platform safety invariants (brand isolation, the
  # active/visible lifecycle, the minimum-age gate, blocks, valid gender/
  # interested_in semantics) live in Matching::VisibilityScope and are NOT
  # configurable here — this type only governs the reciprocal *ranking*
  # constraints layered on top for discovery.
  #
  # `location_max_age` nil means a brand treats a persisted `ProfileLocation` as
  # a chosen dating location that stays valid until the member replaces or
  # removes it, rather than a live/presence signal that must be recently
  # captured. Distance calculation, filtering, and eligibility are unchanged;
  # only the freshness cutoff is skipped.
  #
  # `location_filtering` false removes distance/location from discovery
  # eligibility entirely (a member with no ProfileLocation stays discoverable,
  # and stored distance preferences are not applied).
  #
  # `age_filtering` false removes the reciprocal age-range constraint from
  # discovery eligibility: candidates are not excluded because their stored age
  # bounds are null or because they would otherwise fail D8N's two-sided age
  # filter. Existing age values are never read, modified, or defaulted.
  #
  # `require_age_preferences` false lets a member become a discovery participant
  # (viewer) without `min_age`/`max_age` set. `interested_in` is always still
  # required — that is orientation, not a preference filter.
  EligibilityPolicy = Data.define(
    :location_max_age, :location_filtering, :age_filtering, :require_age_preferences
  ) do
    def initialize(location_max_age: nil, location_filtering: true, age_filtering: true,
      require_age_preferences: true)
      unless location_max_age.nil? || (location_max_age.respond_to?(:ago) && location_max_age.positive?)
        raise ArgumentError, "location_max_age must be nil or a positive duration"
      end
      raise ArgumentError, "location_filtering must be boolean" unless [ true, false ].include?(location_filtering)
      raise ArgumentError, "age_filtering must be boolean" unless [ true, false ].include?(age_filtering)
      unless [ true, false ].include?(require_age_preferences)
        raise ArgumentError, "require_age_preferences must be boolean"
      end

      super
    end

    def location_freshness_required? = location_max_age.present?
  end

  EligibilityPolicy::DEFAULT = EligibilityPolicy.new(location_max_age: 24.hours)
  EligibilityPolicy::PERSISTENT_LOCATION = EligibilityPolicy.new(location_max_age: nil)
  # Date9ja uses country/city profile fields but has no distance-based product
  # behaviour. Location is therefore not part of discovery eligibility.
  EligibilityPolicy::NO_LOCATION = EligibilityPolicy.new(location_filtering: false)
  # Date9ja's established liquidity-first discovery policy: neither location nor
  # age preferences gate participation, and neither distance nor age is an
  # active discovery filter. Orientation reciprocity (gender / interested_in)
  # and every platform safety invariant remain fully enforced.
  EligibilityPolicy::LIQUIDITY_FIRST = EligibilityPolicy.new(
    location_filtering: false, age_filtering: false, require_age_preferences: false
  )
end
