require "test_helper"

module Identity
  class OtpThrottleLockTest < ActiveSupport::TestCase
    self.use_transactional_tests = false

    test "serializes concurrent OTP requests for the same brand and phone" do
      brand = Brand.create!(slug: "otp-lock-#{SecureRandom.hex(6)}", name: "OTP Lock Test")
      results = Queue.new
      start = Queue.new

      threads = 2.times.map do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            start.pop
            results << PhoneOtpRequester.call(
              brand:,
              phone: "+27 82 123 4567",
              ip_address: "192.0.2.10"
            )
          end
        end
      end

      2.times { start << true }
      threads.each(&:join)
      outcomes = 2.times.map { results.pop }

      assert_equal 1, outcomes.count(&:success?)
      assert_equal 1, outcomes.count { |result| result.error == :rate_limited }
      assert_equal 1, OtpChallenge.where(brand:, identifier: "27821234567").count
    ensure
      if brand
        NotificationDelivery.where(brand:).delete_all
        SecurityEvent.where(brand:).delete_all
        AuthAttempt.where(brand:).delete_all
        OtpChallenge.where(brand:).delete_all
        brand.destroy!
      end
    end
  end
end
