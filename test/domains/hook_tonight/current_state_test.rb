require "test_helper"
require_relative "../../support/hook_test_helpers"

module HookTonight
  class CurrentStateTest < ActiveSupport::TestCase
    include HookTestHelpers

    setup do
      @brand = Brand.create!(slug: "hookus", name: "HookUs")
      @member = create_member(brand: @brand)
    end

    test "reports inactive when never activated" do
      state = CurrentState.call(user: @member.user, brand: @brand)

      assert_not state.active
      assert_nil state.expires_at
      assert_nil state.intent
    end

    test "reports the live availability when active" do
      activated = Activate.call(user: @member.user, brand: @brand).state

      state = CurrentState.call(user: @member.user, brand: @brand)

      assert state.active
      assert_equal activated.expires_at.to_i, state.expires_at.to_i
      assert_equal Policy::DEFAULT_INTENT, state.intent
    end

    test "reports inactive for a stale (expired) activation without a sweeper" do
      Activate.call(user: @member.user, brand: @brand).state
        .update_columns(expires_at: 1.hour.ago)

      state = CurrentState.call(user: @member.user, brand: @brand)

      assert_not state.active
      assert_nil state.expires_at
    end

    test "reports inactive after deactivation" do
      Activate.call(user: @member.user, brand: @brand)
      Deactivate.call(user: @member.user, brand: @brand)

      assert_not CurrentState.call(user: @member.user, brand: @brand).active
    end
  end
end
