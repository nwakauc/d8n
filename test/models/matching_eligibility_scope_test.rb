require "test_helper"

module Matching
  class EligibilityScopeTest < ActiveSupport::TestCase
    setup do
      @brand = Brand.create!(slug: "hookus", name: "HookUs")
      @viewer = create_profile(
        brand: @brand, gender: "woman", age: 30,
        interested_in: [ "man" ], min_age: 25, max_age: 40
      )
    end

    test "returns only active visible adult candidates from the current brand" do
      eligible = create_candidate
      create_candidate(profile_attributes: { visibility: :hidden })
      create_candidate(profile_attributes: { status: :draft })
      create_candidate(membership_status: :suspended)
      create_candidate(user_status: :suspended)
      deleted = create_candidate
      deleted.update!(deleted_at: Time.current)
      underage = create_candidate
      underage.update_column(:birthdate, 17.years.ago.to_date)
      other_brand = Brand.create!(slug: "date9ja", name: "Date9ja")
      create_candidate(brand: other_brand)

      assert_equal [ eligible.id ], eligible_scope.pluck(:id)
    end

    test "enforces reciprocal gender and age preferences" do
      eligible = create_candidate
      create_candidate(gender: "nonbinary")
      create_candidate(interested_in: [ "man" ])
      create_candidate(age: 24)
      create_candidate(age: 41)
      create_candidate(min_age: 31)
      create_candidate(max_age: 29)

      assert_equal [ eligible.id ], eligible_scope.pluck(:id)
    end

    test "enforces viewer and candidate distance limits" do
      @viewer.profile_preference.update!(max_distance_km: 20)
      create_location(@viewer, latitude: -33.9249, longitude: 18.4241)
      nearby = create_candidate
      create_location(nearby, latitude: -33.93, longitude: 18.43)
      candidate_too_strict = create_candidate(max_distance_km: 1)
      create_location(candidate_too_strict, latitude: -33.97, longitude: 18.47)
      far = create_candidate
      create_location(far, latitude: -26.2041, longitude: 28.0473)

      assert_equal [ nearby.id ], eligible_scope.pluck(:id)
    end

    test "requires fresh locations only when either side configures distance" do
      no_distance = create_candidate
      distance_candidate = create_candidate(max_distance_km: 50)

      assert_equal [ no_distance.id ], eligible_scope.pluck(:id)

      create_location(@viewer, captured_at: 25.hours.ago)
      assert_equal [ no_distance.id ], eligible_scope.pluck(:id)

      @viewer.profile_locations.first.update!(captured_at: Time.current)
      create_location(distance_candidate, captured_at: 25.hours.ago)
      assert_equal [ no_distance.id ], eligible_scope.pluck(:id)

      distance_candidate.profile_locations.first.update!(captured_at: Time.current)
      assert_equal [ no_distance.id, distance_candidate.id ].sort, eligible_scope.pluck(:id).sort
    end

    test "handles distance across the international date line" do
      @viewer.profile_preference.update!(max_distance_km: 50)
      create_location(@viewer, latitude: 0, longitude: 179.9)
      candidate = create_candidate
      create_location(candidate, latitude: 0, longitude: -179.9)

      assert_equal [ candidate.id ], eligible_scope.pluck(:id)
    end

    test "does not place precise coordinates in SQL text or bind logs" do
      @viewer.profile_preference.update!(max_distance_km: 20)
      create_location(@viewer, latitude: -33.9123456, longitude: 18.4987654)
      candidate = create_candidate
      create_location(candidate, latitude: -33.92, longitude: 18.5)
      events = []
      callback = lambda do |_name, _start, _finish, _id, payload|
        binds = payload.fetch(:binds, []).map do |bind|
          bind.respond_to?(:value_for_database) ? bind.value_for_database : bind.to_s
        end
        events << [ payload[:sql], binds ].inspect
      end

      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { eligible_scope.load }
      logged_query_data = events.join(" ")

      assert_not_includes logged_query_data, "-33.9123456"
      assert_not_includes logged_query_data, "18.4987654"
    end

    private

    def eligible_scope
      EligibilityScope.call(
        brand: @brand,
        viewer: @viewer,
        location_max_age: Strategies::Hookus.location_max_age
      )
    end

    def create_candidate(brand: @brand, **attributes)
      create_profile(brand:, gender: "man", age: 30, interested_in: [ "woman" ],
        min_age: 25, max_age: 40, **attributes)
    end

    def create_profile(brand:, gender:, age:, interested_in:, min_age:, max_age:, max_distance_km: nil,
      profile_attributes: {}, user_status: :active, membership_status: :active)
      user = User.create!(status: user_status)
      membership = BrandMembership.create!(brand:, user:, status: membership_status)
      profile = Profile.create!(
        brand:, user:, brand_membership: membership, gender:, birthdate: age.years.ago.to_date,
        status: :active, visibility: :visible, **profile_attributes
      )
      ProfilePreference.create!(
        brand:, user:, profile:, interested_in:, min_age:, max_age:, max_distance_km:
      )
      profile
    end

    def create_location(profile, latitude: -33.9249, longitude: 18.4241, captured_at: Time.current)
      ProfileLocation.create!(
        profile:, user: profile.user, brand: profile.brand, latitude:, longitude:,
        accuracy_meters: 20, source: "device", captured_at:
      )
    end
  end
end
