require "test_helper"

class ProfileBlockTest < ActiveSupport::TestCase
  setup do
    @brand = Brand.create!(slug: "hookus", name: "HookUs")
    @blocker = create_profile(@brand)
    @blocked = create_profile(@brand)
  end

  test "allows one active directional block and preserves unblocked history" do
    first = ProfileBlock.create!(brand: @brand, blocker_profile: @blocker, blocked_profile: @blocked)
    assert_not ProfileBlock.new(brand: @brand, blocker_profile: @blocker, blocked_profile: @blocked).valid?

    first.update!(deleted_at: Time.current)
    replacement = ProfileBlock.create!(brand: @brand, blocker_profile: @blocker, blocked_profile: @blocked)

    assert_not_equal first.id, replacement.id
    assert_equal 2, ProfileBlock.where(brand: @brand).count
    assert_equal 1, ProfileBlock.kept.where(brand: @brand).count
  end

  test "database rejects self blocks" do
    assert_raises ActiveRecord::StatementInvalid do
      ProfileBlock.insert_all!([ attributes_for(@brand, @blocker, @blocker) ])
    end
  end

  test "database rejects a blocked profile from another brand" do
    other_brand = Brand.create!(slug: "other", name: "Other")
    other_profile = create_profile(other_brand)

    assert_raises ActiveRecord::InvalidForeignKey do
      ProfileBlock.insert_all!([ attributes_for(@brand, @blocker, other_profile) ])
    end
  end

  private

  def create_profile(brand)
    user = User.create!
    membership = BrandMembership.create!(brand:, user:)
    Profile.create!(brand:, user:, brand_membership: membership)
  end

  def attributes_for(brand, blocker, blocked)
    {
      brand_id: brand.id,
      blocker_profile_id: blocker.id,
      blocked_profile_id: blocked.id,
      created_at: Time.current,
      updated_at: Time.current
    }
  end
end
