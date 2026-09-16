require "test_helper"
require_relative "../support/hook_test_helpers"

module HookTonight
  class ActivationConcurrencyTest < ActiveSupport::TestCase
    include HookTestHelpers
    self.use_transactional_tests = false

    test "simultaneous activations converge on exactly one current-state row" do
      brand = Brand.create!(slug: "hookus-#{SecureRandom.hex(6)}", name: "HookUs Race")
      member = create_member(brand:)
      results = Queue.new
      start = Queue.new

      threads = 2.times.map do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            start.pop
            results << Activate.call(user: member.user, brand:)
          rescue StandardError => e
            results << e
          end
        end
      end
      2.times { start << true }
      threads.each(&:join)
      outcomes = 2.times.map { results.pop }

      assert(outcomes.all? { |o| o.is_a?(Activate::Result) }, outcomes.map(&:inspect).join("\n"))
      assert_equal 1, HookTonightState.where(brand:).count
      assert HookTonightState.where(brand:).sole.live?
    ensure
      if brand
        SecurityEvent.where(brand:).delete_all
        HookTonightState.where(brand:).delete_all
        ProfilePreference.where(brand:).delete_all
        AnalyticsEvent.where(brand:).delete_all
        Profile.where(brand:).delete_all
        BrandMembership.where(brand:).delete_all
        brand.destroy!
      end
    end
  end
end
