require "test_helper"
require_relative "../../support/hook_test_helpers"

module Hooks
  class DeclineHookTest < ActiveSupport::TestCase
    include HookTestHelpers

    setup do
      @brand = Brand.create!(slug: "hookus-#{SecureRandom.hex(4)}", name: "HookUs")
      @sender = create_member(brand: @brand)
      @recipient = create_member(brand: @brand)
      @hook = send_hook(sender: @sender, brand: @brand, target: @recipient).hook
    end

    test "the recipient declines a pending hook" do
      Hooks::DeclineHook.call(user: @recipient.user, brand: @brand, hook_public_id: @hook.public_id)

      assert @hook.reload.status_declined?
      assert_not_nil @hook.declined_at
      assert_equal 0, Match.kept.where(brand: @brand).count
      assert SecurityEvent.exists?(event_type: "hooks.declined")
    end

    test "declining does not let the sender hook again (one hook per pair)" do
      Hooks::DeclineHook.call(user: @recipient.user, brand: @brand, hook_public_id: @hook.public_id)

      error = assert_raises(Matching::InteractionError) do
        send_hook(sender: @sender, brand: @brand, target: @recipient)
      end
      assert_equal :already_hooked, error.code
    end

    test "a non-recipient cannot decline" do
      stranger = create_member(brand: @brand)

      error = assert_raises(Messaging::AccessError) do
        Hooks::DeclineHook.call(user: stranger.user, brand: @brand, hook_public_id: @hook.public_id)
      end
      assert_equal :hook_unavailable, error.code
    end

    test "declining an already-declined hook is unavailable" do
      Hooks::DeclineHook.call(user: @recipient.user, brand: @brand, hook_public_id: @hook.public_id)

      assert_raises(Messaging::AccessError) do
        Hooks::DeclineHook.call(user: @recipient.user, brand: @brand, hook_public_id: @hook.public_id)
      end
    end
  end
end
