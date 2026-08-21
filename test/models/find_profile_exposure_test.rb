require "test_helper"

class FindProfileExposureTest < ActiveSupport::TestCase
  setup do
    @brand = Brand.create!(slug: "dateza", name: "DateZA")
    @viewer = create_profile(@brand)
    @candidate = create_profile(@brand)
    @attributes = {
      brand_id: @brand.id,
      user_id: @viewer.user_id,
      brand_membership_id: @viewer.brand_membership_id,
      viewer_profile_id: @viewer.id,
      candidate_profile_id: @candidate.id,
      exposure_date: Date.new(2026, 8, 21),
      created_at: Time.current,
      updated_at: Time.current
    }
  end

  test "database enforces one candidate exposure per membership and day" do
    FindProfileExposure.insert_all!([ @attributes ])

    assert_raises ActiveRecord::RecordNotUnique do
      FindProfileExposure.insert_all!([ @attributes ])
    end
  end

  test "database rejects cross-brand candidate references" do
    other_brand = Brand.create!(slug: "hookus", name: "HookUs")
    other_candidate = create_profile(other_brand)

    assert_raises ActiveRecord::InvalidForeignKey do
      FindProfileExposure.insert_all!([ @attributes.merge(candidate_profile_id: other_candidate.id) ])
    end
  end

  test "database rejects self exposure" do
    assert_raises ActiveRecord::StatementInvalid do
      FindProfileExposure.insert_all!([ @attributes.merge(candidate_profile_id: @viewer.id) ])
    end
  end

  private

  def create_profile(brand)
    user = User.create!
    membership = BrandMembership.create!(brand:, user:)
    Profile.create!(brand:, user:, brand_membership: membership)
  end
end
