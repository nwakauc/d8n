require "test_helper"
require_relative "../../support/hook_test_helpers"

module Hooks
  class ReceivedInboxTest < ActiveSupport::TestCase
    include HookTestHelpers

    setup do
      @brand = Brand.create!(slug: "hookus-#{SecureRandom.hex(4)}", name: "HookUs")
      @recipient = create_member(brand: @brand)
    end

    def inbox(**opts)
      Hooks::ReceivedInbox.call(user: @recipient.user, brand: @brand, **opts)
    end

    test "lists live received hooks newest-first" do
      first = send_hook(sender: create_member(brand: @brand), brand: @brand, target: @recipient).hook
      second = send_hook(sender: create_member(brand: @brand), brand: @brand, target: @recipient).hook
      second.update!(created_at: 1.second.from_now)

      ids = inbox.hooks.map(&:id)
      assert_equal [ second.id, first.id ], ids
    end

    test "omits expired, declined, and accepted hooks" do
      live = send_hook(sender: create_member(brand: @brand), brand: @brand, target: @recipient).hook
      send_hook(sender: create_member(brand: @brand), brand: @brand, target: @recipient).hook.update!(expires_at: 1.hour.ago)
      send_hook(sender: create_member(brand: @brand), brand: @brand, target: @recipient).hook.update!(status: :declined)

      assert_equal [ live.id ], inbox.hooks.map(&:id)
    end

    test "hides hooks from a blocked or suspended sender without leaking them" do
      blocked_sender = create_member(brand: @brand)
      send_hook(sender: blocked_sender, brand: @brand, target: @recipient)
      ProfileBlock.create!(brand: @brand, blocker_profile: @recipient, blocked_profile: blocked_sender)

      suspended_sender = create_member(brand: @brand)
      send_hook(sender: suspended_sender, brand: @brand, target: @recipient)
      suspended_sender.update!(status: :suspended)

      visible_sender = create_member(brand: @brand)
      visible = send_hook(sender: visible_sender, brand: @brand, target: @recipient).hook

      assert_equal [ visible.id ], inbox.hooks.map(&:id)
    end

    test "paginates with a signed cursor" do
      3.times { send_hook(sender: create_member(brand: @brand), brand: @brand, target: @recipient) }

      first_page = inbox(limit: "2")
      assert_equal 2, first_page.hooks.length
      assert first_page.next_cursor.present?

      second_page = inbox(limit: "2", cursor: first_page.next_cursor)
      assert_equal 1, second_page.hooks.length
      assert_nil second_page.next_cursor
    end
  end
end
