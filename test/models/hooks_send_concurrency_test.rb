require "test_helper"
require_relative "../support/hook_test_helpers"

module Hooks
  class SendConcurrencyTest < ActiveSupport::TestCase
    include HookTestHelpers
    self.use_transactional_tests = false

    test "concurrent identical hooks create exactly one, the loser gets already_hooked" do
      brand = Brand.create!(slug: "hookus-#{SecureRandom.hex(6)}", name: "HookUs Race")
      sender = create_member(brand:)
      recipient = create_member(brand:)
      results = Queue.new
      start = Queue.new

      threads = 2.times.map do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            start.pop
            results << Hooks::SendHook.call(
              user: sender.user, brand:, target_public_id: recipient.public_id,
              message: "one shot 🔥",
              eligibility_policy: D8n::Platform::Brands::Hookus::ELIGIBILITY_POLICY
            )
          rescue StandardError => e
            results << e
          end
        end
      end
      2.times { start << true }
      threads.each(&:join)
      outcomes = 2.times.map { results.pop }

      created = outcomes.select { |o| o.is_a?(Hooks::SendHook::Result) }
      errors = outcomes.select { |o| o.is_a?(Matching::InteractionError) }
      assert_equal 1, created.length, outcomes.map(&:inspect).join("\n")
      assert_equal 1, errors.length
      assert_equal :already_hooked, errors.first.code
      assert_equal 1, Hook.where(brand:).count
    ensure
      if brand
        SecurityEvent.where(brand:).delete_all
        Hook.where(brand:).delete_all
        ProfilePreference.where(brand:).delete_all
        Profile.where(brand:).delete_all
        BrandMembership.where(brand:).delete_all
        brand.destroy!
      end
    end

    test "concurrent replies unlock exactly one conversation" do
      brand = Brand.create!(slug: "hookus-#{SecureRandom.hex(6)}", name: "HookUs Reply Race")
      sender = create_member(brand:)
      recipient = create_member(brand:)
      hook = Hooks::SendHook.call(
        user: sender.user, brand:, target_public_id: recipient.public_id,
        message: "opener 🔥", eligibility_policy: D8n::Platform::Brands::Hookus::ELIGIBILITY_POLICY
      ).hook
      results = Queue.new
      start = Queue.new

      threads = 2.times.map do |i|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            start.pop
            results << Hooks::ReplyToHook.call(
              user: recipient.user, brand:, hook_public_id: hook.public_id, message: "reply #{i}"
            )
          rescue StandardError => e
            results << e
          end
        end
      end
      2.times { start << true }
      threads.each(&:join)
      outcomes = 2.times.map { results.pop }

      accepted = outcomes.select { |o| o.is_a?(Hooks::ReplyToHook::Result) }
      assert_equal 1, accepted.length, outcomes.map(&:inspect).join("\n")
      assert_equal 1, Match.kept.status_active.where(brand:).count
      assert_equal 1, Conversation.kept.where(brand:).count
      assert hook.reload.status_accepted?
    ensure
      if brand
        SecurityEvent.where(brand:).delete_all
        Message.where(brand:).delete_all
        Hook.where(brand:).delete_all
        ConversationParticipant.where(brand:).delete_all
        Conversation.where(brand:).delete_all
        Match.where(brand:).delete_all
        ProfilePreference.where(brand:).delete_all
        Profile.where(brand:).delete_all
        BrandMembership.where(brand:).delete_all
        brand.destroy!
      end
    end
  end
end
