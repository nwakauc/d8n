require "test_helper"
require_relative "../../support/hook_test_helpers"

module Hooks
  class ReplyToHookTest < ActiveSupport::TestCase
    include HookTestHelpers

    setup do
      @brand = Brand.create!(slug: "hookus-#{SecureRandom.hex(4)}", name: "HookUs")
      @sender = create_member(brand: @brand)
      @recipient = create_member(brand: @brand)
      @hook = send_hook(sender: @sender, brand: @brand, target: @recipient, message: "opener line 🔥").hook
    end

    def reply(message: "yes let's 🔥", user: @recipient.user)
      Hooks::ReplyToHook.call(user:, brand: @brand, hook_public_id: @hook.public_id, message:)
    end

    test "the recipient's first reply accepts the hook and unlocks a conversation" do
      result = reply

      assert @hook.reload.status_accepted?
      assert_not_nil @hook.accepted_at
      assert_equal result.conversation.id, @hook.conversation_id

      match = Match.kept.status_active.find_by(brand: @brand)
      assert_not_nil match
      assert_equal [ @sender.id, @recipient.id ].sort, [ match.profile_a_id, match.profile_b_id ]
      assert SecurityEvent.exists?(event_type: "hooks.accepted")
    end

    test "the opener becomes the first message and the reply the second" do
      result = reply(message: "sure!")

      messages = Message.kept.where(conversation: result.conversation).order(:created_at, :id).to_a
      assert_equal 2, messages.length
      assert_equal @sender.id, messages.first.sender_profile_id
      assert_equal "opener line 🔥", messages.first.body
      assert_equal @recipient.id, messages.last.sender_profile_id
      assert_equal "sure!", messages.last.body
    end

    test "after acceptance the sender can message through the normal conversation endpoint" do
      result = reply

      sent = Messaging::SendMessage.call(
        user: @sender.user, brand: @brand,
        conversation_public_id: result.conversation.public_id, body: "great, when?"
      )
      assert_equal @sender.id, sent.message.sender_profile_id
      assert_equal 3, Message.kept.where(conversation: result.conversation).count
    end

    test "rejects a blank reply" do
      assert_raises(Messaging::MessageError) { reply(message: "  ") }
      assert @hook.reload.status_pending?
    end

    test "a second reply to an already-accepted hook is unavailable" do
      reply

      error = assert_raises(Messaging::AccessError) { reply(message: "again") }
      assert_equal :hook_unavailable, error.code
    end

    test "cannot reply to an expired hook" do
      @hook.update!(expires_at: 1.minute.ago)

      error = assert_raises(Messaging::AccessError) { reply }
      assert_equal :hook_unavailable, error.code
      assert_equal 0, Match.kept.where(brand: @brand).count
    end

    test "only the recipient may reply" do
      stranger = create_member(brand: @brand)

      error = assert_raises(Messaging::AccessError) { reply(user: stranger.user) }
      assert_equal :hook_unavailable, error.code
    end

    test "cannot reply once the recipient is blocked by the sender" do
      ProfileBlock.create!(brand: @brand, blocker_profile: @sender, blocked_profile: @recipient)

      error = assert_raises(Messaging::AccessError) { reply }
      assert_equal :hook_unavailable, error.code
    end
  end
end
