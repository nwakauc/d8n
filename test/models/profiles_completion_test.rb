require "test_helper"

module Profiles
  class CompletionTest < ActiveSupport::TestCase
    test "returns missing profile and preference fields" do
      profile = build_profile(display_name: "Ada")

      completion = Completion.call(profile:)

      assert_not completion.complete?
      assert_equal 14, completion.percent
      assert_equal [
        :birthdate,
        :gender,
        :"preferences.min_age",
        :"preferences.max_age",
        :"preferences.interested_in",
        :photos
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
      attach_photo(profile)

      completion = Completion.call(profile:)

      assert completion.complete?
      assert_equal 100, completion.percent
      assert_empty completion.missing
    end

    test "uses brand-specific profile completion requirements" do
      brand = Brand.create!(
        slug: "hookus",
        name: "HookUs",
        profile_requirements: {
          profile_fields: [ "display_name" ],
          preference_fields: [],
          collections: []
        }
      )
      user = User.create!
      membership = BrandMembership.create!(brand:, user:)
      profile = Profile.create!(brand:, user:, brand_membership: membership, display_name: "Ada")

      completion = Completion.call(profile:)

      assert completion.complete?
      assert_equal 100, completion.percent
      assert_empty completion.missing
    end

    test "treats a profile with no configured requirements as complete" do
      brand = Brand.create!(
        slug: "hookus",
        name: "HookUs",
        profile_requirements: {
          profile_fields: [],
          preference_fields: [],
          collections: []
        }
      )
      user = User.create!
      membership = BrandMembership.create!(brand:, user:)
      profile = Profile.create!(brand:, user:, brand_membership: membership)

      completion = Completion.call(profile:)

      assert completion.complete?
      assert_equal 100, completion.percent
      assert_empty completion.missing
    end

    test "requires every configured option group" do
      brand = Brand.create!(slug: "hookus", name: "HookUs")
      HookusProfileCatalog.install!(brand:)
      brand.update!(profile_requirements: {
        profile_fields: [], preference_fields: [], collections: [], option_groups: %w[ intents vibes ]
      })
      user = User.create!
      membership = BrandMembership.create!(brand:, user:)
      profile = Profile.create!(brand:, user:, brand_membership: membership)

      OptionSelections.replace!(profile:, selections: { intents: [ "hookups" ] })
      incomplete = Completion.call(profile:)

      assert_not incomplete.complete?
      assert_equal 50, incomplete.percent
      assert_equal [ :"options.vibes" ], incomplete.missing

      OptionSelections.replace!(profile:, selections: { vibes: [ "chill" ] })
      complete = Completion.call(profile:)

      assert complete.complete?
      assert_equal 100, complete.percent
    end

    test "reports informational sections without affecting completeness" do
      profile = build_profile(display_name: "Ada", bio: "Hello", smoking: "never")

      completion = Completion.call(profile:)
      sections = completion.sections

      assert_equal %w[ photos bio basics intent lifestyle interests prompts verification ].to_set,
        sections.keys.to_set
      assert sections.fetch("bio").fetch(:complete)
      assert sections.fetch("lifestyle").fetch(:complete) # smoking column counts
      assert_not sections.fetch("photos").fetch(:complete)
      assert_not sections.fetch("prompts").fetch(:complete)
      assert_not sections.fetch("verification").fetch(:complete)
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

    def attach_photo(profile)
      photo = ProfilePhoto.new(profile:, user: profile.user, brand: profile.brand)
      photo.image.attach(
        io: Rails.root.join("test/fixtures/files/profile_photo.png").open,
        filename: "profile_photo.png",
        content_type: "image/png"
      )
      photo.save!
    end
  end
end
