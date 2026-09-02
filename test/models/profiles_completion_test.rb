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

    test "photo completion requires a safe publication-eligible derivative" do
      profile = build_profile
      raw_only = attach_photo(profile, ready: false)
      assert_includes Completion.call(profile:).missing, :photos

      raw_only.display_image.attach(
        io: Rails.root.join("test/fixtures/files/profile_photo.png").open,
        filename: "display.jpg", content_type: "image/jpeg"
      )
      raw_only.update!(processing_state: :ready, status: :rejected, visibility: :visible)
      assert_includes Completion.call(profile:).missing, :photos

      raw_only.update!(status: :approved, visibility: :hidden)
      assert_includes Completion.call(profile:).missing, :photos

      raw_only.update!(visibility: :visible)
      assert_not_includes Completion.call(profile:).missing, :photos
    end

    test "a visible pending DateZA photo can complete onboarding only after safe processing" do
      brand = Brand.create!(
        slug: "dateza", name: "DateZA",
        profile_requirements: { profile_fields: [], preference_fields: [], collections: %w[ photos ] }
      )
      user = User.create!
      membership = BrandMembership.create!(brand:, user:)
      profile = Profile.create!(brand:, user:, brand_membership: membership)
      # Forces visibility: :visible explicitly (matching DateZA's actual
      # immediate-visibility default) to isolate the processing-readiness
      # gate from the moderation-policy gate.
      photo = attach_photo(profile, visibility: :visible, ready: false)

      assert_not Completion.call(profile:).complete?
      assert_not photo.deliverable?

      photo.display_image.attach(
        io: Rails.root.join("test/fixtures/files/profile_photo.png").open,
        filename: "display.jpg", content_type: "image/jpeg"
      )
      photo.update!(processing_state: :ready)

      assert Completion.call(profile:).complete?
      assert photo.reload.deliverable?, "processed pending photos are immediately deliverable on DateZA"
    end

    test "a hidden pending photo on a moderate-first brand satisfies onboarding completion but remains non-deliverable" do
      # A brand with no registered contract fails closed to moderate-first
      # (date9ja now uses an explicit immediate policy — see Media::PhotoPolicy).
      brand = Brand.create!(
        slug: "unregistered-brand", name: "Unregistered",
        profile_requirements: { profile_fields: [], preference_fields: [], collections: %w[ photos ] }
      )
      user = User.create!
      membership = BrandMembership.create!(brand:, user:)
      profile = Profile.create!(brand:, user:, brand_membership: membership)
      photo = attach_photo(profile, visibility: :hidden)

      # Moderate-first brands (see Media::PhotoPolicy): a processed,
      # still-pending photo is enough to finish onboarding — the member isn't
      # forced back into an incomplete state while awaiting review — but the
      # photo itself stays non-deliverable to anyone but its owner until an
      # admin approves it.
      assert Completion.call(profile:).complete?
      assert_not photo.deliverable?
    end

    test "HookUs hidden pending photo does not satisfy publication" do
      profile = build_profile
      profile.brand.update!(profile_requirements: {
        profile_fields: [], preference_fields: [], collections: %w[ photos ]
      })
      attach_photo(profile, visibility: :hidden)

      assert_not Completion.call(profile:).complete?
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

    test "requires location only for brands that configure it as a collection" do
      brand = Brand.create!(
        slug: "dateza",
        name: "DateZA",
        profile_requirements: { profile_fields: [], preference_fields: [], collections: %w[ location ] }
      )
      user = User.create!
      membership = BrandMembership.create!(brand:, user:)
      profile = Profile.create!(brand:, user:, brand_membership: membership)

      incomplete = Completion.call(profile:)
      assert_not incomplete.complete?
      assert_equal [ :location ], incomplete.missing

      ProfileLocation.create!(
        brand:, user:, profile:, latitude: -26.2041, longitude: 28.0473,
        accuracy_meters: 25, source: "device", captured_at: Time.current
      )

      assert Completion.call(profile:).complete?
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

    test "informational verification counts only verified contact identifiers" do
      profile = build_profile(display_name: "Ada")
      IdentityIdentifier.create!(
        user: profile.user, kind: :oauth_provider_uid,
        normalized_value: "provider:subject", verified_at: Time.current
      )

      assert_not Completion.call(profile:).sections.fetch("verification").fetch(:complete)

      IdentityIdentifier.create!(
        user: profile.user, kind: :email,
        normalized_value: "ada@example.com", verified_at: Time.current
      )

      assert Completion.call(profile:).sections.fetch("verification").fetch(:complete)
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

    def attach_photo(profile, visibility: :visible, ready: true)
      photo = ProfilePhoto.new(profile:, user: profile.user, brand: profile.brand, visibility:)
      photo.image.attach(
        io: Rails.root.join("test/fixtures/files/profile_photo.png").open,
        filename: "profile_photo.png",
        content_type: "image/png"
      )
      photo.save!
      if ready
        photo.display_image.attach(
          io: Rails.root.join("test/fixtures/files/profile_photo.png").open,
          filename: "display.jpg",
          content_type: "image/jpeg"
        )
        photo.update!(processing_state: :ready)
      end
      photo
    end
  end
end
