require "test_helper"

module Identity
  class Date9jaPhoneVerificationPolicyTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    test "VerificationRequester cannot create or deliver a Date9ja phone challenge" do
      brand = Brand.create!(slug: "date9ja", name: "Date9ja", auth_methods: %w[phone_password email_password])
      user = User.create!
      BrandMembership.create!(brand:, user:, status: :active)
      user.identity_identifiers.create!(kind: :phone, normalized_value: "2348012345678")
      Notifications::Sms::TestGateway.clear

      previous = ENV["D8N_SMS_PROVIDER"]
      ENV["D8N_SMS_PROVIDER"] = "test"
      result = nil
      assert_no_difference -> { OtpChallenge.count } do
        assert_no_enqueued_jobs only: Notifications::DeliverChallengeJob do
          result = VerificationRequester.call(user:, brand:, kind: :phone)
        end
      end

      assert_not result.success?
      assert_equal :verification_unavailable, result.error
      assert_empty Notifications::Sms::TestGateway.deliveries
    ensure
      previous.nil? ? ENV.delete("D8N_SMS_PROVIDER") : ENV["D8N_SMS_PROVIDER"] = previous
    end
  end
end
