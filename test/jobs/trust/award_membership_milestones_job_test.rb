require "test_helper"

class Trust::AwardMembershipMilestonesJobTest < ActiveJob::TestCase
  setup do
    @brand = Brand.create!(slug: "date9ja", name: "Date9ja")
  end

  test "awards every milestone a profile has already reached, and none it hasn't" do
    profile = build_profile(created_at: 4.months.ago)

    Trust::AwardMembershipMilestonesJob.perform_now

    assert_equal 20, TrustEvent.find_by(brand: @brand, user: profile.user, event_type: "membership_one_month").points
    assert_equal 50, TrustEvent.find_by(brand: @brand, user: profile.user, event_type: "membership_three_months").points
    assert_nil TrustEvent.find_by(brand: @brand, user: profile.user, event_type: "membership_six_months")
    assert_nil TrustEvent.find_by(brand: @brand, user: profile.user, event_type: "membership_one_year")
  end

  test "is idempotent across repeated runs" do
    build_profile(created_at: 4.months.ago)

    2.times { Trust::AwardMembershipMilestonesJob.perform_now }

    assert_equal 2, TrustEvent.where(brand: @brand).count
  end

  private

  def build_profile(created_at:)
    user = User.create!
    membership = BrandMembership.create!(brand: @brand, user:)
    profile = Profile.create!(brand: @brand, user:, brand_membership: membership)
    profile.update_column(:created_at, created_at)
    profile
  end
end
