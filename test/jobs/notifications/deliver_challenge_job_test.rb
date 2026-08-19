require "test_helper"

module Notifications
  class DeliverChallengeJobTest < ActiveJob::TestCase
    setup do
      @brand = Brand.create!(slug: "hookus", name: "HookUs")
      @user = User.create!
      BrandMembership.create!(brand: @brand, user: @user, status: :active)
      @phone = @user.identity_identifiers.create!(kind: :phone, normalized_value: "27821234567", verified_at: Time.current)
      Notifications::Sms::TestGateway.clear
    end

    test "delivers the code through the provider and clears the ciphertext" do
      challenge = create_challenge(code: "123456")

      with_sms_provider("test") { DeliverChallengeJob.perform_now(challenge.id) }

      assert_equal "27821234567", Notifications::Sms::TestGateway.deliveries.last.fetch(:to)
      assert_includes Notifications::Sms::TestGateway.deliveries.last.fetch(:body), "123456"
      assert_nil challenge.reload.delivery_code, "delivery_code must be cleared after a successful send"
    end

    test "a duplicate run after success does not send again" do
      challenge = create_challenge(code: "123456")
      with_sms_provider("test") { DeliverChallengeJob.perform_now(challenge.id) }
      Notifications::Sms::TestGateway.clear

      with_sms_provider("test") { DeliverChallengeJob.perform_now(challenge.id) }

      assert_empty Notifications::Sms::TestGateway.deliveries
    end

    test "skips a missing, consumed, or expired challenge without delivering" do
      DeliverChallengeJob.perform_now(-1)

      consumed = create_challenge(code: "111111")
      consumed.consume!
      expired = create_challenge(code: "222222", expires_at: 1.minute.ago)

      with_sms_provider("test") do
        DeliverChallengeJob.perform_now(consumed.id)
        DeliverChallengeJob.perform_now(expired.id)
      end

      assert_empty Notifications::Sms::TestGateway.deliveries
    end

    test "a permanent failure clears the code and does not retry" do
      challenge = create_challenge(code: "123456")
      permanent = Identity::ChallengeDelivery::Result.new(success?: false, retryable: false)

      assert_no_enqueued_jobs do
        stub_method(Identity::ChallengeDelivery, :call, ->(*_a, **_k) { permanent }) { DeliverChallengeJob.perform_now(challenge.id) }
      end

      assert_nil challenge.reload.delivery_code
    end

    test "a transient failure retries and keeps the code for redelivery" do
      challenge = create_challenge(code: "123456")
      transient = Identity::ChallengeDelivery::Result.new(success?: false, retryable: true)

      assert_enqueued_jobs 1, only: DeliverChallengeJob do
        stub_method(Identity::ChallengeDelivery, :call, ->(*_a, **_k) { transient }) { DeliverChallengeJob.perform_now(challenge.id) }
      end

      assert_equal "123456", challenge.reload.delivery_code, "code must survive so a retry can resend"
    end

    private

    def create_challenge(code:, expires_at: 10.minutes.from_now, kind: :password_recovery)
      OtpChallenge.create!(
        brand: @brand, identity_identifier: @phone, kind:,
        identifier: @phone.normalized_value, code_digest: OtpChallenge.digest_code(code),
        delivery_code: code, expires_at:, metadata: { purpose: "password_recovery" }
      )
    end

    def with_sms_provider(provider)
      previous = ENV["D8N_SMS_PROVIDER"]
      ENV["D8N_SMS_PROVIDER"] = provider
      yield
    ensure
      ENV["D8N_SMS_PROVIDER"] = previous
    end
  end
end
