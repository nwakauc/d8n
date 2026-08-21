module Matching
  module Find
    class Filter
      class Invalid < StandardError; end

      Result = Data.define(:min_age, :max_age, :max_distance_km, :relationship_intent) do
        def cursor_key
          [ min_age, max_age, max_distance_km, relationship_intent ].join(":")
        end
      end

      def self.parse(brand:, min_age: nil, max_age: nil, max_distance_km: nil, relationship_intent: nil)
        parsed_min_age = parse_integer(min_age, range: ProfilePreference::MINIMUM_AGE..ProfilePreference::MAXIMUM_AGE)
        parsed_max_age = parse_integer(max_age, range: ProfilePreference::MINIMUM_AGE..ProfilePreference::MAXIMUM_AGE)
        parsed_distance = parse_integer(max_distance_km, range: 1..ProfilePreference::MAX_DISTANCE_KM)
        if parsed_min_age && parsed_max_age && parsed_min_age > parsed_max_age
          raise Invalid, "minimum age cannot exceed maximum age"
        end

        intent = relationship_intent.to_s.presence
        validate_intent!(brand:, intent:) if intent
        Result.new(parsed_min_age, parsed_max_age, parsed_distance, intent)
      rescue ArgumentError, TypeError
        raise Invalid, "Find filters are invalid"
      end

      def self.apply(scope:, brand:, viewer:, policy:, filter:)
        scope = apply_age(scope:, filter:)
        scope = apply_distance(scope:, viewer:, policy:, filter:)
        apply_relationship_intent(scope:, brand:, filter:)
      end

      def self.parse_integer(value, range:)
        return if value.blank?

        parsed = Integer(value.to_s, 10)
        raise Invalid, "Find filters are invalid" unless range.cover?(parsed)

        parsed
      end
      private_class_method :parse_integer

      def self.validate_intent!(brand:, intent:)
        available = brand.profile_option_groups.kept.status_active
          .find_by(key: "relationship_intent")
          &.profile_options&.kept&.status_active&.exists?(code: intent)
        raise Invalid, "Find filters are invalid" unless available
      end
      private_class_method :validate_intent!

      def self.apply_age(scope:, filter:)
        if filter.min_age
          scope = scope.where("profiles.birthdate <= ?", filter.min_age.years.ago.to_date)
        end
        if filter.max_age
          scope = scope.where("profiles.birthdate > ?", (filter.max_age + 1).years.ago.to_date)
        end
        scope
      end
      private_class_method :apply_age

      def self.apply_distance(scope:, viewer:, policy:, filter:)
        return scope unless filter.max_distance_km

        fresh_location = viewer.profile_locations.kept.where(captured_at: policy.location_max_age.ago..).exists?
        return scope.none unless fresh_location

        scope.where("#{EligibilityScope::DISTANCE_SQL} <= ?", filter.max_distance_km)
      end
      private_class_method :apply_distance

      def self.apply_relationship_intent(scope:, brand:, filter:)
        return scope unless filter.relationship_intent

        matching_profiles = ProfileOptionSelection.kept.where(brand:)
          .joins(:profile_option_group, :profile_option)
          .merge(ProfileOptionGroup.kept.status_active)
          .merge(ProfileOption.kept.status_active)
          .where(
            profile_option_groups: { key: "relationship_intent" },
            profile_options: { code: filter.relationship_intent }
          ).select(:profile_id)
        scope.where(id: matching_profiles)
      end
      private_class_method :apply_relationship_intent
    end
  end
end
