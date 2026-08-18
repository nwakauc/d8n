require "test_helper"
require_relative "../../support/hook_test_helpers"

module HookTonight
  class DeactivateTest < ActiveSupport::TestCase
    include HookTestHelpers

    setup do
      @brand = Brand.create!(slug: "hookus", name: "HookUs")
      @member = create_member(brand: @brand)
    end

    test "deactivating an active member takes them out of the live pool immediately" do
      state = Activate.call(user: @member.user, brand: @brand).state

      Deactivate.call(user: @member.user, brand: @brand)

      assert_not state.reload.live?
      assert_not_includes HookTonightState.live.where(brand: @brand), state
      assert SecurityEvent.exists?(brand: @brand, user: @member.user, event_type: "hook_tonight.deactivated")
    end

    test "deactivating when never activated is a safe no-op with no event" do
      assert_nothing_raised do
        Deactivate.call(user: @member.user, brand: @brand)
      end
      assert_not SecurityEvent.exists?(brand: @brand, event_type: "hook_tonight.deactivated")
    end

    test "repeat deactivation is idempotent and emits only one event" do
      Activate.call(user: @member.user, brand: @brand)

      Deactivate.call(user: @member.user, brand: @brand)
      Deactivate.call(user: @member.user, brand: @brand)

      assert_equal 1, SecurityEvent.where(brand: @brand, event_type: "hook_tonight.deactivated").count
    end

    test "a suspended member can still turn availability off" do
      Activate.call(user: @member.user, brand: @brand)
      @member.update!(status: :suspended)

      assert_nothing_raised do
        Deactivate.call(user: @member.user, brand: @brand)
      end
      assert_empty HookTonightState.live.where(brand: @brand)
    end
  end
end
