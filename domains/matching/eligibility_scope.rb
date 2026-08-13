module Matching
  class EligibilityScope
    EARTH_RADIUS_KM = 6_371.0
    KM_PER_LATITUDE_DEGREE = 110.574
    KM_PER_LONGITUDE_DEGREE = 111.320
    DISTANCE_SQL = <<~SQL.squish.freeze
      #{EARTH_RADIUS_KM} * 2 * ASIN(LEAST(1, SQRT(
        POWER(SIN(RADIANS(candidate_locations.latitude - viewer_location.latitude) / 2), 2) +
        COS(RADIANS(viewer_location.latitude)) * COS(RADIANS(candidate_locations.latitude)) *
        POWER(SIN(RADIANS(candidate_locations.longitude - viewer_location.longitude) / 2), 2)
      )))
    SQL

    def self.call(brand:, viewer:, location_max_age:)
      new(brand:, viewer:, location_max_age:).call
    end

    def initialize(brand:, viewer:, location_max_age:)
      @brand = brand
      @viewer = viewer
      @viewer_preference = viewer.profile_preference
      @location_cutoff = location_max_age.ago
    end

    def call
      scope = lifecycle_scope
      scope = reciprocal_gender_scope(scope)
      scope = reciprocal_age_scope(scope)
      distance_scope(scope)
    end

    private

    attr_reader :brand, :viewer, :viewer_preference, :location_cutoff

    def lifecycle_scope
      brand.profiles.kept.active.visible
        .where.not(id: viewer.id)
        .joins(:user, :brand_membership, :profile_preference)
        .merge(User.kept.active)
        .merge(BrandMembership.kept.active)
        .where(profile_preferences: { deleted_at: nil })
        .where.not(birthdate: nil)
        .where("profiles.birthdate <= ?", Profile::MINIMUM_AGE.years.ago.to_date)
    end

    def reciprocal_gender_scope(scope)
      scope.where(gender: viewer_preference.interested_in)
        .where("profile_preferences.interested_in @> ?::jsonb", [ viewer.gender ].to_json)
    end

    def reciprocal_age_scope(scope)
      scope = scope.where("profiles.birthdate <= ?", viewer_preference.min_age.years.ago.to_date)
      scope = scope.where("profiles.birthdate > ?", (viewer_preference.max_age + 1).years.ago.to_date)
      scope.where("profile_preferences.min_age <= ?", viewer_age)
        .where("profile_preferences.max_age >= ?", viewer_age)
    end

    def distance_scope(scope)
      location = viewer_location
      return without_viewer_location(scope) if location.blank?

      scope = join_candidate_locations(scope)
      scope = within_viewer_distance(scope) if viewer_preference.max_distance_km.present?
      within_candidate_distance(scope)
    end

    def without_viewer_location(scope)
      return scope.none if viewer_preference.max_distance_km.present?

      scope.where(profile_preferences: { max_distance_km: nil })
    end

    def join_candidate_locations(scope)
      scope.joins(<<~SQL.squish).joins(<<~SQL.squish)
        INNER JOIN profile_locations viewer_location
          ON viewer_location.id = #{Integer(viewer_location.id)}
          AND viewer_location.profile_id = #{Integer(viewer.id)}
          AND viewer_location.brand_id = profiles.brand_id
          AND viewer_location.deleted_at IS NULL
          AND viewer_location.captured_at >= #{ProfileLocation.connection.quote(location_cutoff)}
      SQL
        LEFT JOIN profile_locations candidate_locations
          ON candidate_locations.profile_id = profiles.id
          AND candidate_locations.brand_id = profiles.brand_id
          AND candidate_locations.deleted_at IS NULL
          AND candidate_locations.captured_at >= #{ProfileLocation.connection.quote(location_cutoff)}
      SQL
    end

    def within_viewer_distance(scope)
      max_distance = viewer_preference.max_distance_km
      scope = scope.where.not(candidate_locations: { id: nil })
        .where(
          "candidate_locations.latitude BETWEEN " \
            "GREATEST(-90, viewer_location.latitude - ?) AND " \
            "LEAST(90, viewer_location.latitude + ?)",
          max_distance / KM_PER_LATITUDE_DEGREE,
          max_distance / KM_PER_LATITUDE_DEGREE
        )
        .where(
          "ABS(MOD(candidate_locations.longitude - viewer_location.longitude + 540, 360) - 180) <= " \
            "LEAST(180, ? / (#{KM_PER_LONGITUDE_DEGREE} * " \
            "GREATEST(ABS(COS(RADIANS(viewer_location.latitude))), 0.0001)))",
          max_distance
        )
      scope.where("#{DISTANCE_SQL} <= ?", max_distance)
    end

    def within_candidate_distance(scope)
      scope.where(
        "profile_preferences.max_distance_km IS NULL OR " \
          "(candidate_locations.id IS NOT NULL AND #{DISTANCE_SQL} <= profile_preferences.max_distance_km)"
      )
    end

    def viewer_location
      @viewer_location ||= viewer.profile_locations.kept.where(captured_at: location_cutoff..).order(captured_at: :desc).first
    end

    def viewer_age
      @viewer_age ||= begin
        today = Date.current
        birthday_passed = (today.month * 100 + today.day) >= (viewer.birthdate.month * 100 + viewer.birthdate.day)
        today.year - viewer.birthdate.year - (birthday_passed ? 0 : 1)
      end
    end
  end
end
