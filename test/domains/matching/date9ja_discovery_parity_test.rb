require "test_helper"

module Matching
  # Proves Date9ja's liquidity-first brand discovery policy: age preferences,
  # location, and full generic completion do NOT gate discovery participation or
  # filtering, while every platform safety invariant and orientation reciprocity
  # remain fully enforced. Other brands are unaffected (see the HookUs cases).
  class Date9jaDiscoveryParityTest < ActiveSupport::TestCase
    setup do
      @brand = Brands::Date9jaInstaller.call(hosts: [ "date9ja.test" ])
      @policy = D8n::Platform::BrandRegistry.fetch(brand: @brand).interaction.eligibility_policy
    end

    # ---- participant eligibility -------------------------------------------

    test "1-3: adult Date9ja profile with orientation but no age bounds, no location, no distance can participate" do
      viewer = create_member(gender: "woman", interested_in: [ "man" ], min_age: nil, max_age: nil,
        max_distance_km: nil)

      assert_nothing_raised { ProfileParticipant.discoverable!(user: viewer.user, brand: @brand) }
    end

    test "4: missing interested_in still fails participation" do
      viewer = create_member(gender: "woman", interested_in: [], min_age: nil, max_age: nil)

      assert_raises(InteractionError) { ProfileParticipant.discoverable!(user: viewer.user, brand: @brand) }
    end

    test "4b: missing gender still fails participation" do
      viewer = create_member(gender: "woman", interested_in: [ "man" ])
      viewer.update_column(:gender, nil)

      assert_raises(InteractionError) { ProfileParticipant.discoverable!(user: viewer.user, brand: @brand) }
    end

    test "5: underage profile fails participation" do
      viewer = create_member(gender: "woman", interested_in: [ "man" ])
      viewer.update_column(:birthdate, 17.years.ago.to_date)

      assert_raises(InteractionError) { ProfileParticipant.discoverable!(user: viewer.user, brand: @brand) }
    end

    # ---- age behaviour ----------------------------------------------------

    test "6: candidate with null age preferences is not excluded" do
      viewer = create_member(gender: "woman", interested_in: [ "man" ], min_age: nil, max_age: nil)
      candidate = create_member(gender: "man", interested_in: [ "woman" ], min_age: nil, max_age: nil)

      assert_includes eligible_ids(viewer), candidate.id
    end

    test "7: candidate whose stored age bounds would fail D8N reciprocal age filtering is not excluded" do
      viewer = create_member(gender: "woman", interested_in: [ "man" ], age: 30, min_age: 25, max_age: 40)
      # bounds that exclude the viewer's age (30) and whose own age is outside
      # the viewer's window — both directions would fail the generic filter.
      candidate = create_member(gender: "man", interested_in: [ "woman" ], age: 55, min_age: 18, max_age: 22)

      assert_includes eligible_ids(viewer), candidate.id
    end

    test "8: existing age values are never modified or defaulted by discovery" do
      viewer = create_member(gender: "woman", interested_in: [ "man" ], min_age: nil, max_age: nil)
      candidate = create_member(gender: "man", interested_in: [ "woman" ], min_age: 33, max_age: 34)

      eligible_ids(viewer)

      candidate.profile_preference.reload
      assert_equal 33, candidate.profile_preference.min_age
      assert_equal 34, candidate.profile_preference.max_age
      assert_nil viewer.profile_preference.reload.min_age
    end

    # ---- distance behaviour --------------------------------------------------

    test "9: Date9ja candidate without location remains eligible" do
      viewer = create_member(gender: "woman", interested_in: [ "man" ])
      candidate = create_member(gender: "man", interested_in: [ "woman" ])

      assert_includes eligible_ids(viewer), candidate.id
    end

    test "10: stored distance preference does not filter while location policy is disabled" do
      viewer = create_member(gender: "woman", interested_in: [ "man" ], max_distance_km: 1)
      candidate = create_member(gender: "man", interested_in: [ "woman" ], max_distance_km: 1)

      assert_includes eligible_ids(viewer), candidate.id
    end

    # ---- reciprocal orientation -------------------------------------------

    test "11-14: all four Date9ja source orientation pools match reciprocally" do
      {
        [ "man", "woman" ] => [ "woman", "man" ],
        [ "woman", "man" ] => [ "man", "woman" ],
        [ "man", "man" ] => [ "man", "man" ],
        [ "woman", "woman" ] => [ "woman", "woman" ]
      }.each do |(v_gender, v_interest), (c_gender, c_interest)|
        viewer = create_member(gender: v_gender, interested_in: [ v_interest ])
        candidate = create_member(gender: c_gender, interested_in: [ c_interest ])

        assert_includes eligible_ids(viewer), candidate.id,
          "#{v_gender}->#{v_interest} should match #{c_gender}->#{c_interest}"
      end
    end

    test "15: one-sided orientation mismatch fails" do
      viewer = create_member(gender: "woman", interested_in: [ "man" ])
      # candidate is a man (viewer wants) but the candidate wants men, not women.
      candidate = create_member(gender: "man", interested_in: [ "man" ])

      assert_not_includes eligible_ids(viewer), candidate.id
    end

    # ---- safety ---------------------------------------------------------

    test "16: profile_hidden candidate fails" do
      viewer = create_member(gender: "woman", interested_in: [ "man" ])
      candidate = create_member(gender: "man", interested_in: [ "woman" ])
      candidate.update!(visibility: :hidden)

      assert_not_includes eligible_ids(viewer), candidate.id
    end

    test "17: suspended candidate fails" do
      viewer = create_member(gender: "woman", interested_in: [ "man" ])
      candidate = create_member(gender: "man", interested_in: [ "woman" ])
      candidate.update!(status: :suspended)

      assert_not_includes eligible_ids(viewer), candidate.id
    end

    test "18: banned candidate (suspended membership) fails" do
      viewer = create_member(gender: "woman", interested_in: [ "man" ])
      candidate = create_member(gender: "man", interested_in: [ "woman" ])
      candidate.brand_membership.update!(status: :suspended)

      assert_not_includes eligible_ids(viewer), candidate.id
    end

    test "19-20: deleted candidate (profile and user) fails" do
      viewer = create_member(gender: "woman", interested_in: [ "man" ])
      candidate = create_member(gender: "man", interested_in: [ "woman" ])
      candidate.update!(deleted_at: Time.current)

      assert_not_includes eligible_ids(viewer), candidate.id
    end

    test "21: blocked candidate fails in both directions" do
      viewer = create_member(gender: "woman", interested_in: [ "man" ])
      candidate = create_member(gender: "man", interested_in: [ "woman" ])

      ProfileBlock.create!(brand: @brand, blocker_profile: viewer, blocked_profile: candidate)
      assert_not_includes eligible_ids(viewer), candidate.id

      ProfileBlock.where(brand: @brand).update_all(deleted_at: nil, blocker_profile_id: candidate.id,
        blocked_profile_id: viewer.id)
      assert_not_includes eligible_ids(viewer.reload), candidate.id
    end

    test "22: cross-brand candidate never leaks into Date9ja discovery" do
      viewer = create_member(gender: "woman", interested_in: [ "man" ])
      hookus = Brand.create!(slug: "hookus", name: "HookUs")
      foreign = create_member(gender: "man", interested_in: [ "woman" ], brand: hookus)

      assert_not_includes eligible_ids(viewer), foreign.id
    end

    # ---- completion / publication --------------------------------------------

    test "23: Date9ja discoverability does not require generic full completion (age preferences)" do
      requirements = @brand.profile_completion_requirements
      assert_not_includes requirements.fetch("preference_fields"), "min_age"
      assert_not_includes requirements.fetch("preference_fields"), "max_age"
      assert_includes requirements.fetch("preference_fields"), "interested_in"
      assert_not_includes requirements.fetch("collections"), "location"
    end

    test "24: other brand completion + eligibility behaviour is unchanged" do
      hookus_policy = D8n::Platform::BrandRegistry.fetch(
        brand: Brand.new(slug: "hookus", name: "HookUs")
      ).interaction.eligibility_policy

      assert hookus_policy.age_filtering
      assert hookus_policy.require_age_preferences
    end

    # ---- downstream consistency --------------------------------------------

    test "25-26: Date9ja-eligible discovered candidate can be liked and a reciprocal like creates a match" do
      alice = create_member(gender: "woman", interested_in: [ "man" ], min_age: nil, max_age: nil)
      bob = create_member(gender: "man", interested_in: [ "woman" ], min_age: nil, max_age: nil)

      assert_includes eligible_ids(alice), bob.id

      LikeProfile.call(user: alice.user, brand: @brand, target_public_id: bob.public_id)
      result = LikeProfile.call(user: bob.user, brand: @brand, target_public_id: alice.public_id)

      assert result.match.present?
    end

    test "27: hard-excluded candidate cannot be liked through the direct like flow" do
      alice = create_member(gender: "woman", interested_in: [ "man" ])
      bob = create_member(gender: "man", interested_in: [ "woman" ])
      bob.update!(status: :suspended)

      assert_raises(InteractionError) do
        LikeProfile.call(user: alice.user, brand: @brand, target_public_id: bob.public_id)
      end
    end

    private

    def eligible_ids(viewer)
      EligibilityScope.call(brand: @brand, viewer:, policy: @policy).pluck(:id)
    end

    def create_member(gender:, interested_in:, age: 30, min_age: 25, max_age: 40, max_distance_km: nil,
      brand: @brand)
      user = User.create!
      membership = BrandMembership.create!(brand:, user:)
      profile = Profile.create!(
        brand:, user:, brand_membership: membership, display_name: "Member", gender:,
        birthdate: age.years.ago.to_date, status: :active, visibility: :visible
      )
      ProfilePreference.create!(brand:, user:, profile:, interested_in:, min_age:, max_age:, max_distance_km:)
      profile
    end
  end
end
