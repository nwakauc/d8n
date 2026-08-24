module Matching
  EligibilityPolicy = Data.define(:location_max_age) do
    def initialize(location_max_age:)
      unless location_max_age.respond_to?(:ago) && location_max_age.positive?
        raise ArgumentError, "location_max_age must be a positive duration"
      end

      super
    end
  end

  EligibilityPolicy::DEFAULT = EligibilityPolicy.new(location_max_age: 24.hours)
end
