require "test_helper"

class Hq::Member360::DiscoveryDiagnosticTest < ActiveSupport::TestCase
  setup do
    @brand = Brand.create!(slug: "hookus", name: "HookUs")
    @viewer = create_profile(brand: @brand, gender: "woman", interested_in: [ "man" ])
  end

  test "reports the funnel down to a final eligible candidate" do
    candidate = create_profile(brand: @brand, gender: "man", interested_in: [ "woman" ])

    result = Hq::Member360::DiscoveryDiagnostic.call(brand: @brand, profile: @viewer)

    assert result.eligible
    assert_nil result.ineligibility_reason
    stage_names = result.stages.map(&:stage)
    assert_equal %w[visible_active_profiles reciprocal_gender_age_distance final_eligible_candidates], stage_names
    assert_equal 1, result.stages.last.candidate_count
    assert candidate.persisted?
  end

  test "an incomplete profile is reported ineligible with a reason, not an exception" do
    incomplete_user = User.create!
    membership = BrandMembership.create!(brand: @brand, user: incomplete_user)
    incomplete_profile = Profile.create!(
      brand: @brand, user: incomplete_user, brand_membership: membership,
      birthdate: 30.years.ago.to_date, status: :active, visibility: :visible
      # no gender / preference -- deliberately incomplete
    )

    result = Hq::Member360::DiscoveryDiagnostic.call(brand: @brand, profile: incomplete_profile)

    assert_equal false, result.eligible
    assert_equal "profile_unavailable", result.ineligibility_reason
    assert_equal [], result.stages
  end

  test "excludes an already-liked candidate from the final stage without touching quotas" do
    liked = create_profile(brand: @brand, gender: "man", interested_in: [ "woman" ])
    Like.create!(brand: @brand, liker_profile: @viewer, liked_profile: liked)

    assert_no_difference -> { DiscoveryAllocation.count } do
      result = Hq::Member360::DiscoveryDiagnostic.call(brand: @brand, profile: @viewer)
      assert_equal 0, result.stages.last.candidate_count
    end
  end

  private

  def create_profile(brand:, gender:, interested_in:)
    user = User.create!
    membership = BrandMembership.create!(brand:, user:)
    profile = Profile.create!(
      brand:, user:, brand_membership: membership, gender:, birthdate: 30.years.ago.to_date,
      status: :active, visibility: :visible
    )
    ProfilePreference.create!(brand:, user:, profile:, interested_in:, min_age: 21, max_age: 45)
    profile
  end
end
