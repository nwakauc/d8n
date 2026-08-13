require "test_helper"

class ProfilePassTest < ActiveSupport::TestCase
  test "validates directed uniqueness and no self-pass" do
    brand, first, second = profile_pair
    ProfilePass.create!(brand:, passer_profile: first, passed_profile: second)
    duplicate = ProfilePass.new(brand:, passer_profile: first, passed_profile: second)
    self_pass = ProfilePass.new(brand:, passer_profile: first, passed_profile: first)

    assert_not duplicate.valid?
    assert_not self_pass.valid?
    assert self_pass.errors[:passed_profile].present?
  end

  test "database rejects a cross-brand participant" do
    brand, first, = profile_pair
    other_brand = Brand.create!(slug: "date9ja", name: "Date9ja")
    other = create_profile(other_brand)

    assert_raises ActiveRecord::InvalidForeignKey do
      ProfilePass.insert_all!([ {
        brand_id: brand.id,
        passer_profile_id: first.id,
        passed_profile_id: other.id,
        created_at: Time.current,
        updated_at: Time.current
      } ])
    end
  end

  test "database rejects a self-pass" do
    brand, first, = profile_pair

    assert_raises ActiveRecord::StatementInvalid do
      ProfilePass.insert_all!([ {
        brand_id: brand.id,
        passer_profile_id: first.id,
        passed_profile_id: first.id,
        created_at: Time.current,
        updated_at: Time.current
      } ])
    end
  end

  private

  def profile_pair
    brand = Brand.create!(slug: "hookus", name: "HookUs")
    [ brand, create_profile(brand), create_profile(brand) ]
  end

  def create_profile(brand)
    user = User.create!
    membership = BrandMembership.create!(brand:, user:)
    Profile.create!(brand:, user:, brand_membership: membership)
  end
end
