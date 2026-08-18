require "test_helper"
require_relative "../../support/hook_test_helpers"

module HookTonight
  class ActivateTest < ActiveSupport::TestCase
    include HookTestHelpers

    setup do
      @brand = Brand.create!(slug: "hookus", name: "HookUs")
      @member = create_member(brand: @brand)
    end

    test "activates an eligible member with a fresh expiry and audit event" do
      freeze_time do
        result = Activate.call(user: @member.user, brand: @brand)

        assert result.state.live?
        assert_equal Policy::EXPIRES_IN.from_now, result.state.expires_at
        assert_equal Policy::DEFAULT_INTENT, result.state.intent
        assert SecurityEvent.exists?(brand: @brand, user: @member.user, event_type: "hook_tonight.activated")
      end
    end

    test "re-activation reuses the single row and refreshes the expiry" do
      first = Activate.call(user: @member.user, brand: @brand).state
      first.update_columns(expires_at: 1.minute.from_now, deactivated_at: Time.current)

      second = Activate.call(user: @member.user, brand: @brand).state

      assert_equal first.id, second.id
      assert_equal 1, HookTonightState.where(brand: @brand, profile: @member).count
      assert_nil second.deactivated_at
      assert_operator second.expires_at, :>, 1.hour.from_now
    end

    test "rejects an unsupported intent before touching the database" do
      assert_raises Policy::InvalidIntent do
        Activate.call(user: @member.user, brand: @brand, intent: "netflix")
      end
      assert_empty HookTonightState.where(brand: @brand)
    end

    test "a suspended member cannot activate" do
      @member.update!(status: :suspended)

      assert_raises Matching::InteractionError do
        Activate.call(user: @member.user, brand: @brand)
      end
      assert_empty HookTonightState.where(brand: @brand)
    end

    test "a closed (discarded) member cannot activate" do
      @member.update!(deleted_at: Time.current)

      assert_raises Matching::InteractionError do
        Activate.call(user: @member.user, brand: @brand)
      end
      assert_empty HookTonightState.where(brand: @brand)
    end
  end
end
