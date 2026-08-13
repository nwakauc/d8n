require "test_helper"

class LikeTest < ActiveSupport::TestCase
  test "validates directed uniqueness and no self-like" do
    brand, first, second = profile_pair
    Like.create!(brand:, liker_profile: first, liked_profile: second)
    duplicate = Like.new(brand:, liker_profile: first, liked_profile: second)
    self_like = Like.new(brand:, liker_profile: first, liked_profile: first)

    assert_not duplicate.valid?
    assert_not self_like.valid?
    assert self_like.errors[:liked_profile].present?
  end

  test "database rejects a cross-brand participant" do
    brand, first, = profile_pair
    other_brand = Brand.create!(slug: "date9ja", name: "Date9ja")
    other = create_profile(other_brand)

    assert_raises ActiveRecord::InvalidForeignKey do
      Like.insert_all!([ {
        brand_id: brand.id,
        liker_profile_id: first.id,
        liked_profile_id: other.id,
        kind: Like.kinds.fetch("like"),
        created_at: Time.current,
        updated_at: Time.current
      } ])
    end
  end

  test "database rejects a self-like" do
    brand, first, = profile_pair

    assert_raises ActiveRecord::StatementInvalid do
      Like.insert_all!([ {
        brand_id: brand.id,
        liker_profile_id: first.id,
        liked_profile_id: first.id,
        kind: Like.kinds.fetch("like"),
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
