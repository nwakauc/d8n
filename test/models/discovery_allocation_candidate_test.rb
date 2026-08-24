require "test_helper"

class DiscoveryAllocationCandidateTest < ActiveSupport::TestCase
  test "rejects a cross-brand candidate" do
    dateza = Brand.create!(slug: "dateza", name: "DateZA")
    other_brand = Brand.create!(slug: "allocation-other", name: "Other")
    viewer = create_profile(dateza)
    candidate = create_profile(other_brand)
    allocation = DiscoveryAllocation.create!(
      brand: dateza, user: viewer.user, brand_membership: viewer.brand_membership,
      viewer_profile: viewer, surface_key: "discovery.curated_daily",
      allocation_date: Date.current, time_zone: "UTC", daily_limit: 10,
      strategy_key: "test", policy_key: "test", finalized_at: Time.current
    )

    item = allocation.allocation_candidates.new(
      brand: dateza, candidate_profile: candidate, position: 1,
      ranking_payload: { compatibility: nil }
    )

    assert_not item.valid?
    assert_includes item.errors[:base], "records must belong to the same brand"
  end

  private

  def create_profile(brand)
    user = User.create!
    membership = BrandMembership.create!(brand:, user:)
    Profile.create!(brand:, user:, brand_membership: membership)
  end
end
