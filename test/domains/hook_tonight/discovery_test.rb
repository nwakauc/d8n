require "test_helper"
require_relative "../../support/hook_test_helpers"

module HookTonight
  class DiscoveryTest < ActiveSupport::TestCase
    include HookTestHelpers

    setup do
      @brand = Brand.create!(slug: "hookus", name: "HookUs")
      @viewer = create_member(brand: @brand, gender: "woman", interested_in: %w[man])
      # Access is reciprocal: the viewer must be in the pool to see the pool.
      Activate.call(user: @viewer.user, brand: @brand)
    end

    def discovered_ids
      Discovery.call(user: @viewer.user, brand: @brand).profiles.map(&:id)
    end

    def compatible_candidate
      create_member(brand: @brand, gender: "man", interested_in: %w[woman])
    end

    test "raises NotActivated when the viewer is not in the pool" do
      Deactivate.call(user: @viewer.user, brand: @brand)
      candidate = compatible_candidate
      Activate.call(user: candidate.user, brand: @brand)

      assert_raises(Discovery::NotActivated) { discovered_ids }
    end

    test "includes a compatible member with a live availability" do
      candidate = compatible_candidate
      Activate.call(user: candidate.user, brand: @brand)

      assert_equal [ candidate.id ], discovered_ids
    end

    test "excludes an eligible member who has not activated" do
      compatible_candidate

      assert_empty discovered_ids
    end

    test "excludes a member whose availability has expired" do
      candidate = compatible_candidate
      Activate.call(user: candidate.user, brand: @brand).state.update_columns(expires_at: 1.hour.ago)

      assert_empty discovered_ids
    end

    test "excludes a member who deactivated" do
      candidate = compatible_candidate
      Activate.call(user: candidate.user, brand: @brand)
      Deactivate.call(user: candidate.user, brand: @brand)

      assert_empty discovered_ids
    end

    test "excludes the viewer even when the viewer is available" do
      Activate.call(user: @viewer.user, brand: @brand)
      candidate = compatible_candidate
      Activate.call(user: candidate.user, brand: @brand)

      assert_equal [ candidate.id ], discovered_ids
    end

    test "excludes a member blocked in either direction" do
      blocked = compatible_candidate
      Activate.call(user: blocked.user, brand: @brand)
      ProfileBlock.create!(brand: @brand, blocker_profile: @viewer, blocked_profile: blocked)

      assert_empty discovered_ids

      ProfileBlock.where(brand: @brand).delete_all
      ProfileBlock.create!(brand: @brand, blocker_profile: blocked, blocked_profile: @viewer)

      assert_empty discovered_ids
    end

    test "excludes a suspended member despite a stale activation" do
      candidate = compatible_candidate
      Activate.call(user: candidate.user, brand: @brand)
      candidate.update!(status: :suspended)

      assert_empty discovered_ids
    end

    test "excludes a closed (discarded) member despite a stale activation" do
      candidate = compatible_candidate
      Activate.call(user: candidate.user, brand: @brand)
      candidate.update!(deleted_at: Time.current)

      assert_empty discovered_ids
    end

    test "excludes an incompatible member even when available" do
      incompatible = create_member(brand: @brand, gender: "man", interested_in: %w[man])
      Activate.call(user: incompatible.user, brand: @brand)

      assert_empty discovered_ids
    end

    test "excludes an available member on another brand" do
      other_brand = Brand.create!(slug: "other", name: "Other")
      candidate = create_member(brand: other_brand, gender: "man", interested_in: %w[woman])
      Activate.call(user: candidate.user, brand: other_brand)

      assert_empty discovered_ids
    end

    test "excludes a member the viewer already has a live Hook with" do
      candidate = compatible_candidate
      Activate.call(user: candidate.user, brand: @brand)
      send_hook(sender: @viewer, brand: @brand, target: candidate)

      assert_empty discovered_ids
    end
  end
end
