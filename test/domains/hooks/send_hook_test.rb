require "test_helper"
require_relative "../../support/hook_test_helpers"

module Hooks
  class SendHookTest < ActiveSupport::TestCase
    include HookTestHelpers

    setup do
      @brand = Brand.create!(slug: "hookus-#{SecureRandom.hex(4)}", name: "HookUs")
      @sender = create_member(brand: @brand)
      @recipient = create_member(brand: @brand)
    end

    test "creates a pending hook carrying the sender's opener" do
      result = send_hook(sender: @sender, brand: @brand, target: @recipient, message: "  hey you 🔥  ")

      assert result.hook.status_pending?
      assert_equal "hey you 🔥", result.hook.message.strip
      assert_equal @sender.id, result.hook.sender_profile_id
      assert_equal @recipient.id, result.hook.recipient_profile_id
      # No conversation/match/message materializes until the recipient replies.
      assert_nil result.hook.conversation_id
      assert_equal 0, Match.kept.where(brand: @brand).count
      assert_equal 0, Message.where(brand: @brand).count
      assert SecurityEvent.exists?(event_type: "hooks.sent")
    end

    test "accepts the edited or default text verbatim as the opener" do
      result = send_hook(sender: @sender, brand: @brand, target: @recipient, message: "totally custom line")

      assert_equal "totally custom line", result.hook.message
    end

    test "rejects a blank opener before creating anything" do
      assert_raises(Messaging::MessageError) do
        send_hook(sender: @sender, brand: @brand, target: @recipient, message: "   ")
      end
      assert_equal 0, Hook.where(brand: @brand).count
    end

    test "rejects a self hook" do
      error = assert_raises(Matching::InteractionError) do
        send_hook(sender: @sender, brand: @brand, target: @sender)
      end
      assert_equal :profile_unavailable, error.code
    end

    test "rejects a duplicate hook to the same person" do
      send_hook(sender: @sender, brand: @brand, target: @recipient)

      error = assert_raises(Matching::InteractionError) do
        send_hook(sender: @sender, brand: @brand, target: @recipient)
      end
      assert_equal :already_hooked, error.code
    end

    test "rejects hooking a blocked counterpart in either direction" do
      ProfileBlock.create!(brand: @brand, blocker_profile: @recipient, blocked_profile: @sender)

      error = assert_raises(Matching::InteractionError) do
        send_hook(sender: @sender, brand: @brand, target: @recipient)
      end
      assert_equal :profile_unavailable, error.code
    end

    test "rejects hooking a suspended counterpart" do
      @recipient.update!(status: :suspended)

      error = assert_raises(Matching::InteractionError) do
        send_hook(sender: @sender, brand: @brand, target: @recipient)
      end
      assert_equal :profile_unavailable, error.code
    end

    test "rejects a suspended sender" do
      @sender.update!(status: :suspended)

      assert_raises(Matching::InteractionError) do
        send_hook(sender: @sender, brand: @brand, target: @recipient)
      end
    end

    test "rejects a closed sender account" do
      @sender.brand_membership.update!(status: :left)

      assert_raises(Matching::InteractionError) do
        send_hook(sender: @sender, brand: @brand, target: @recipient)
      end
    end

    test "rejects a cross-brand target" do
      other_brand = Brand.create!(slug: "hookus-#{SecureRandom.hex(4)}", name: "Other")
      stranger = create_member(brand: other_brand)

      error = assert_raises(Matching::InteractionError) do
        send_hook(sender: @sender, brand: @brand, target: stranger)
      end
      assert_equal :profile_unavailable, error.code
    end

    test "rejects hooking someone already matched" do
      profile_a_id, profile_b_id = Match.canonical_pair(@sender.id, @recipient.id)
      Match.create!(brand: @brand, profile_a_id:, profile_b_id:, status: :active)

      error = assert_raises(Matching::InteractionError) do
        send_hook(sender: @sender, brand: @brand, target: @recipient)
      end
      assert_equal :already_matched, error.code
    end

    test "tells the sender to reply when the target already hooked them" do
      send_hook(sender: @recipient, brand: @brand, target: @sender)

      error = assert_raises(Matching::InteractionError) do
        send_hook(sender: @sender, brand: @brand, target: @recipient)
      end
      assert_equal :incoming_hook, error.code
    end

    test "supersedes a prior pass from the sender" do
      pass = ProfilePass.create!(brand: @brand, passer_profile: @sender, passed_profile: @recipient)

      send_hook(sender: @sender, brand: @brand, target: @recipient)

      assert_not_nil pass.reload.deleted_at
    end

    test "enforces the daily hook allowance" do
      Hooks::Policy::FREE_DAILY_LIMIT.times do
        send_hook(sender: @sender, brand: @brand, target: create_member(brand: @brand))
      end

      error = assert_raises(Matching::InteractionError) do
        send_hook(sender: @sender, brand: @brand, target: create_member(brand: @brand))
      end
      assert_equal :hook_rate_limited, error.code
      assert_operator error.retry_after, :>, 0
    end
  end
end
