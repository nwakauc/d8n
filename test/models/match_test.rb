require "test_helper"

class MatchTest < ActiveSupport::TestCase
  test "requires canonical participants and assigns a public UUID" do
    brand, first, second = profile_pair
    low, high = [ first, second ].sort_by(&:id)
    match = Match.create!(brand:, profile_a: low, profile_b: high)
    reversed = Match.new(brand:, profile_a: high, profile_b: low)

    assert_match Profile::PUBLIC_ID_FORMAT, match.public_id
    assert_not reversed.valid?
    assert reversed.errors[:base].present?
  end

  test "database rejects a cross-brand participant" do
    brand, first, second = profile_pair
    other_brand = Brand.create!(slug: "date9ja", name: "Date9ja")
    other = create_profile(other_brand)
    profile_a_id, profile_b_id = [ first.id, other.id ].sort

    assert_raises ActiveRecord::InvalidForeignKey do
      Match.insert_all!([ {
        brand_id: brand.id,
        profile_a_id:,
        profile_b_id:,
        public_id: SecureRandom.uuid,
        status: Match.statuses.fetch("active"),
        created_at: Time.current,
        updated_at: Time.current
      } ])
    end
    assert_equal brand, second.brand
  end

  test "database rejects non-canonical participants" do
    brand, first, second = profile_pair
    high, low = [ first, second ].sort_by(&:id).reverse

    assert_raises ActiveRecord::StatementInvalid do
      Match.insert_all!([ {
        brand_id: brand.id,
        profile_a_id: high.id,
        profile_b_id: low.id,
        public_id: SecureRandom.uuid,
        status: Match.statuses.fetch("active"),
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
