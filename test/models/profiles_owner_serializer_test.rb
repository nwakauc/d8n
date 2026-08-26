require "test_helper"

module Profiles
  # Contract test for "owner preview" (My Profile / How You Appear): the owner
  # payload is the ONLY thing that view can be built from, since
  # Matching::VisibilityScope excludes the viewer's own profile — there is no
  # backend path that resolves a member's own public_id back through
  # PublicSerializer/DetailSerializer. Viewer-relative concepts (distance,
  # compatibility) only exist on that excluded path, so they can never leak into
  # self-preview by construction. This test guards that invariant against a
  # future regression, not just documents it.
  class OwnerSerializerTest < ActiveSupport::TestCase
    setup do
      @brand = Brand.create!(slug: "hookus", name: "HookUs")
      @user = User.create!
      @membership = BrandMembership.create!(brand: @brand, user: @user)
      @profile = Profile.create!(
        brand: @brand, user: @user, brand_membership: @membership,
        display_name: "Ada", birthdate: 25.years.ago.to_date, gender: "woman"
      )
    end

    test "never exposes viewer-relative distance or self-compatibility" do
      payload = OwnerSerializer.call(profile: @profile)

      assert_not payload.key?(:distance_km)
      assert_not payload.key?(:compatibility)
      assert_not payload.key?(:opener_state)
      assert_not payload.key?(:hook_state)
    end

    test "own public_id is excluded from the visibility scope other members are resolved through" do
      assert_not Matching::VisibilityScope.call(brand: @brand, viewer: @profile).exists?(id: @profile.id)
    end
  end
end
