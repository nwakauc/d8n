require "test_helper"

module Matching
  # DateZA models ProfileLocation as a chosen dating location, not a live
  # presence signal (see D8n::Platform::Brands::Dateza::ELIGIBILITY_POLICY):
  # once persisted it stays valid for matching regardless of `captured_at`
  # age. HookUs's own 24h freshness requirement is covered separately by
  # test/models/matching_eligibility_scope_test.rb, which is unaffected by
  # this DateZA-only policy.
  class EligibilityScopeDatezaLocationTest < ActiveSupport::TestCase
    setup do
      @brand = Brand.create!(slug: "dateza", name: "DateZA")
      @viewer = create_profile(
        brand: @brand, gender: "woman", age: 30,
        interested_in: [ "man" ], min_age: 25, max_age: 40, max_distance_km: 100
      )
      create_location(@viewer, latitude: -33.9249, longitude: 18.4241)
    end

    test "a candidate with a freshly captured location is eligible" do
      candidate = create_candidate(max_distance_km: 100)
      create_location(candidate, latitude: -33.93, longitude: 18.43, captured_at: Time.current)

      assert_equal [ candidate.id ], eligible_scope.pluck(:id)
    end

    test "a candidate remains eligible after 24 hours" do
      candidate = create_candidate(max_distance_km: 100)
      create_location(candidate, latitude: -33.93, longitude: 18.43, captured_at: 25.hours.ago)

      assert_equal [ candidate.id ], eligible_scope.pluck(:id)
    end

    test "a candidate remains eligible substantially later" do
      candidate = create_candidate(max_distance_km: 100)
      create_location(candidate, latitude: -33.93, longitude: 18.43, captured_at: 90.days.ago)

      assert_equal [ candidate.id ], eligible_scope.pluck(:id)
    end

    test "distance limits still exclude sufficiently distant candidates regardless of age" do
      far = create_candidate(max_distance_km: 100)
      create_location(far, latitude: -26.2041, longitude: 28.0473, captured_at: 90.days.ago)

      assert_empty eligible_scope.pluck(:id)
    end

    test "a candidate with no location record is excluded" do
      create_candidate(max_distance_km: 100)

      assert_empty eligible_scope.pluck(:id)
    end

    test "updating location immediately changes distance eligibility" do
      candidate = create_candidate(max_distance_km: 100)
      location = create_location(candidate, latitude: -26.2041, longitude: 28.0473, captured_at: 90.days.ago)
      assert_empty eligible_scope.pluck(:id)

      location.update!(latitude: -33.93, longitude: 18.43, captured_at: 90.days.ago)

      assert_equal [ candidate.id ], eligible_scope.pluck(:id)
    end

    private

    def eligible_scope
      EligibilityScope.call(
        brand: @brand,
        viewer: @viewer,
        policy: D8n::Platform::Brands::Dateza::ELIGIBILITY_POLICY
      )
    end

    def create_candidate(brand: @brand, **attributes)
      create_profile(brand:, gender: "man", age: 30, interested_in: [ "woman" ],
        min_age: 25, max_age: 40, **attributes)
    end

    def create_profile(brand:, gender:, age:, interested_in:, min_age:, max_age:, max_distance_km: nil,
      profile_attributes: {})
      user = User.create!
      membership = BrandMembership.create!(brand:, user:)
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
