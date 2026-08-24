require "test_helper"

module Identity
  class OtpThrottleLockTest < ActiveSupport::TestCase
    self.use_transactional_tests = false

    test "serializes concurrent verification requests for the same brand and identifier" do
      brand = Brand.create!(
        slug: "otp-lock-#{SecureRandom.hex(6)}",
        name: "OTP Lock Test"
      )
      user = User.create!
      BrandMembership.create!(brand:, user:)
      identity_identifier = user.identity_identifiers.create!(
        kind: :phone,
        normalized_value: "+27 82 123 4567"
      )
      results = Queue.new
      start = Queue.new

      threads = 2.times.map do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            start.pop
            results << VerificationRequester.call(
              user:,
              brand:,
              kind: :phone,
              ip_address: "192.0.2.10"
            )
          end
        end
      end

      2.times { start << true }
      threads.each(&:join)
      outcomes = 2.times.map { results.pop }

      assert_equal 1, outcomes.count(&:success?)
      throttled = outcomes.find { |result| result.error == :verification_resend_too_soon }
      assert throttled
      assert throttled.retry_after.positive?
      assert_equal 1, OtpChallenge.phone_verification.where(brand:, identity_identifier:).count
      assert_equal 1, AuthAttempt.phone_otp.throttled.where(brand:, identity_identifier:).count
    ensure
      if brand
        NotificationDelivery.where(brand:).delete_all
        SecurityEvent.where(brand:).delete_all
        AuthAttempt.where(brand:).delete_all
        OtpChallenge.where(brand:).delete_all
        Credential.where(user:).delete_all if user
        IdentityIdentifier.where(user:).delete_all if user
        BrandMembership.where(brand:).delete_all
        user&.delete
        brand.destroy!
      end
    end
  end
end
