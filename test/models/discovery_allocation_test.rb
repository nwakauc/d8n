require "test_helper"

class DiscoveryAllocationTest < ActiveSupport::TestCase
  test "rejects member and viewer records from another tenant" do
    first_brand = Brand.create!(slug: "allocation-first", name: "First")
    second_brand = Brand.create!(slug: "allocation-second", name: "Second")
    viewer = create_profile(first_brand)
    other = create_profile(second_brand)

    allocation = DiscoveryAllocation.new(
      brand: first_brand, user: viewer.user, brand_membership: viewer.brand_membership,
      viewer_profile: other, surface_key: "discovery.curated_daily",
      allocation_date: Date.current, time_zone: "UTC", daily_limit: 10,
      strategy_key: "test", policy_key: "test", finalized_at: Time.current
    )

    assert_not allocation.valid?
    assert_includes allocation.errors[:base], "records must belong to the same member and brand"
  end

  private

  def create_profile(brand)
    user = User.create!
    membership = BrandMembership.create!(brand:, user:)
    Profile.create!(brand:, user:, brand_membership: membership)
  end
end
