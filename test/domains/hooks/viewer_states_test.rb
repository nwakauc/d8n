require "test_helper"
require_relative "../../support/hook_test_helpers"

module Hooks
  class ViewerStatesTest < ActiveSupport::TestCase
    include HookTestHelpers

    setup do
      @brand = Brand.create!(slug: "hookus-#{SecureRandom.hex(4)}", name: "HookUs")
      @viewer = create_member(brand: @brand)
    end

    def state_for(target)
      Hooks::ViewerStates.call(viewer: @viewer, profiles: [ target ]).fetch(target.id)
    end

    test "available when there is no relationship" do
      assert_equal ViewerStates::AVAILABLE, state_for(create_member(brand: @brand))
    end

    test "pending for a live outgoing hook" do
      target = create_member(brand: @brand)
      send_hook(sender: @viewer, brand: @brand, target:)

      assert_equal ViewerStates::PENDING, state_for(target)
    end

    test "hooked once an active match exists" do
      target = create_member(brand: @brand)
      profile_a_id, profile_b_id = Match.canonical_pair(@viewer.id, target.id)
      Match.create!(brand: @brand, profile_a_id:, profile_b_id:, status: :active)

      assert_equal ViewerStates::HOOKED, state_for(target)
    end

    test "unavailable after the viewer's one hook resolves (declined/expired)" do
      target = create_member(brand: @brand)
      hook = send_hook(sender: @viewer, brand: @brand, target:).hook
      hook.update!(status: :declined, declined_at: Time.current)

      assert_equal ViewerStates::UNAVAILABLE, state_for(target)
    end

    test "unavailable when the other person has a live hook waiting on the viewer" do
      other = create_member(brand: @brand)
      send_hook(sender: other, brand: @brand, target: @viewer)

      assert_equal ViewerStates::UNAVAILABLE, state_for(other)
    end

    test "unavailable when the viewer already liked them" do
      target = create_member(brand: @brand)
      Like.create!(brand: @brand, liker_profile: @viewer, liked_profile: target, kind: :like)

      assert_equal ViewerStates::UNAVAILABLE, state_for(target)
    end

    test "resolves a whole page in a bounded number of queries" do
      targets = 5.times.map { create_member(brand: @brand) }
      send_hook(sender: @viewer, brand: @brand, target: targets.first)

      queries = count_select_queries do
        result = Hooks::ViewerStates.call(viewer: @viewer, profiles: targets)
        assert_equal targets.length, result.size
      end
      # Fixed set of aggregate lookups regardless of page size (matches/outgoing/
      # incoming/likes), never one-per-profile.
      assert_operator queries, :<=, 5
    end

    private

    def count_select_queries
      count = 0
      callback = lambda do |_name, _start, _finish, _id, payload|
        count += 1 if payload[:sql].match?(/\ASELECT/i) && payload[:name] != "SCHEMA"
      end
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
      count
    end
  end
end
