require "test_helper"

module Matching
  class ProfileParticipantTest < ActiveSupport::TestCase
    setup do
      @brand = Brand.create!(slug: "hookus", name: "HookUs")
    end

    test "returns the one active published visible adult profile with complete preferences" do
      profile = create_discoverable_profile

      assert_equal profile, ProfileParticipant.discoverable!(user: profile.user, brand: @brand)
    end

    test "fails closed for every discoverable-viewer lifecycle and preference restriction" do
      mutations = {
        suspended_user: ->(profile) { profile.user.update!(status: :suspended) },
        deleted_user: ->(profile) { profile.user.update_column(:deleted_at, Time.current) },
        suspended_membership: ->(profile) { profile.brand_membership.update!(status: :suspended) },
        left_membership: ->(profile) { profile.brand_membership.update!(status: :left) },
        deleted_membership: ->(profile) { profile.brand_membership.update_column(:deleted_at, Time.current) },
        draft_profile: ->(profile) { profile.update!(status: :draft) },
        suspended_profile: ->(profile) { profile.update!(status: :suspended) },
        hidden_profile: ->(profile) { profile.update!(visibility: :hidden) },
        missing_birthdate: ->(profile) { profile.update_column(:birthdate, nil) },
        underage_profile: ->(profile) { profile.update_column(:birthdate, 17.years.ago.to_date) },
        missing_gender: ->(profile) { profile.update_column(:gender, nil) },
        missing_min_age: ->(profile) { profile.profile_preference.update_column(:min_age, nil) },
        missing_max_age: ->(profile) { profile.profile_preference.update_column(:max_age, nil) },
        missing_interest: ->(profile) { profile.profile_preference.update_column(:interested_in, []) },
        deleted_preference: ->(profile) { profile.profile_preference.update_column(:deleted_at, Time.current) }
      }

      mutations.each do |name, mutation|
        profile = create_discoverable_profile
        mutation.call(profile)

        error = assert_raises(InteractionError) do
          ProfileParticipant.discoverable!(user: profile.user, brand: @brand)
        end
        assert_equal :profile_unavailable, error.code, name
      end
    end

    test "keeps match membership validation distinct from discoverability" do
      profile = create_discoverable_profile
      profile.update!(status: :draft, visibility: :hidden)

      assert_raises(InteractionError) do
        ProfileParticipant.discoverable!(user: profile.user, brand: @brand)
      end
      assert_equal profile, ProfileParticipant.match_member!(user: profile.user, brand: @brand)
    end

    private

    def create_discoverable_profile
      user = User.create!
      membership = BrandMembership.create!(brand: @brand, user:)
      profile = Profile.create!(
        brand: @brand, user:, brand_membership: membership,
        status: :active, visibility: :visible, birthdate: 30.years.ago.to_date, gender: "woman"
      )
      ProfilePreference.create!(
        brand: @brand, user:, profile:, interested_in: [ "man" ], min_age: 25, max_age: 40
      )
      profile
    end
  end
end
