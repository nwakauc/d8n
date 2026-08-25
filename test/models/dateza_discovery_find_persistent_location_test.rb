require "test_helper"

# End-to-end proof that DateZA Discovery and Find — the real controller entry
# points (Api::V1::DiscoveryController, Api::V1::FindController) — surface a
# candidate whose ProfileLocation is old but still persisted, per
# D8n::Platform::Brands::Dateza::ELIGIBILITY_POLICY. HookUs's own 24h
# requirement is unaffected (see test/models/matching_eligibility_scope_test.rb).
class DatezaDiscoveryFindPersistentLocationTest < ActiveSupport::TestCase
  setup do
    @brand = Brand.create!(slug: "dateza", name: "DateZA")
    @viewer_user = User.create!
    @viewer_membership = BrandMembership.create!(brand: @brand, user: @viewer_user)
    @viewer = create_profile(user: @viewer_user, membership: @viewer_membership,
      gender: "woman", age: 30, interested_in: [ "man" ], min_age: 25, max_age: 40, max_distance_km: 100)
    create_location(@viewer, latitude: -33.9249, longitude: 18.4241)

    @candidate = create_candidate(max_distance_km: 100)
    create_location(@candidate, latitude: -33.93, longitude: 18.43, captured_at: 10.days.ago)
  end

  test "DateZA curated Discovery surfaces a candidate with a stale but persisted location" do
    result = Matching::Discovery.call(user: @viewer_user, brand: @brand)

    assert_equal [ @candidate.id ], result.profiles.map(&:id)
  end

  test "DateZA Find surfaces a candidate with a stale but persisted location" do
    result = Matching::Find::Search.call(user: @viewer_user, brand: @brand)

    assert_equal [ @candidate.id ], result.profiles.map(&:id)
  end

  private

  def create_candidate(**attributes)
    user = User.create!
    membership = BrandMembership.create!(brand: @brand, user:)
    create_profile(user:, membership:, gender: "man", age: 30, interested_in: [ "woman" ],
      min_age: 25, max_age: 40, **attributes)
  end

  def create_profile(user:, membership:, gender:, age:, interested_in:, min_age:, max_age:, max_distance_km: nil)
    profile = Profile.create!(
      brand: @brand, user:, brand_membership: membership, gender:, birthdate: age.years.ago.to_date,
      status: :active, visibility: :visible
    )
    ProfilePreference.create!(
      brand: @brand, user:, profile:, interested_in:, min_age:, max_age:, max_distance_km:
    )
    profile
  end

  def create_location(profile, latitude:, longitude:, captured_at: Time.current)
    ProfileLocation.create!(
      profile:, user: profile.user, brand: profile.brand, latitude:, longitude:,
      accuracy_meters: 20, source: "device", captured_at:
    )
  end
end
