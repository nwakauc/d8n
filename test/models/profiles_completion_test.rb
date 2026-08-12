require "test_helper"

module Profiles
  class CompletionTest < ActiveSupport::TestCase
    test "returns missing profile and preference fields" do
      profile = build_profile(display_name: "Ada")

      completion = Completion.call(profile:)

      assert_not completion.complete?
      assert_equal 17, completion.percent
      assert_equal [
        :birthdate,
        :gender,
        :"preferences.min_age",
        :"preferences.max_age",
        :"preferences.interested_in"
      ], completion.missing
    end

    test "returns complete when required profile and preference fields are present" do
      profile = build_profile(
        display_name: "Ada",
        birthdate: 25.years.ago.to_date,
        gender: "woman"
      )
      ProfilePreference.create!(
        profile:,
        user: profile.user,
        brand: profile.brand,
        min_age: 25,
        max_age: 35,
        interested_in: [ "man" ]
      )

      completion = Completion.call(profile:)

      assert completion.complete?
      assert_equal 100, completion.percent
      assert_empty completion.missing
    end

    private

    def build_profile(attributes = {})
      brand = Brand.create!(slug: "hookus", name: "HookUs")
      user = User.create!
      membership = BrandMembership.create!(brand:, user:)

      Profile.create!(
        {
          brand:,
          user:,
          brand_membership: membership
        }.merge(attributes)
      )
    end
  end
end
