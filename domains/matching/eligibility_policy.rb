module Matching
  # `location_max_age` nil means a brand treats a persisted `ProfileLocation` as
  # a chosen dating location that stays valid until the member replaces or
  # removes it, rather than a live/presence signal that must be recently
  # captured. Distance calculation, filtering, and eligibility are unchanged;
  # only the freshness cutoff is skipped.
  EligibilityPolicy = Data.define(:location_max_age) do
    def initialize(location_max_age: nil)
      unless location_max_age.nil? || (location_max_age.respond_to?(:ago) && location_max_age.positive?)
        raise ArgumentError, "location_max_age must be nil or a positive duration"
      end

      super
    end

    def location_freshness_required? = location_max_age.present?
  end

  EligibilityPolicy::DEFAULT = EligibilityPolicy.new(location_max_age: 24.hours)
  EligibilityPolicy::PERSISTENT_LOCATION = EligibilityPolicy.new(location_max_age: nil)
end
