require "test_helper"

module Identity
  # Guards the security-critical invariants of moving OTP delivery off the request
  # transaction: the code is encrypted at rest, the async job carries only an id
  # (never the plaintext), and delivery is enqueued after commit — not inside the
  # transaction/advisory lock.
  class AsyncDeliveryTest < ActiveJob::TestCase
    setup do
      @brand = Brand.create!(slug: "hookus", name: "HookUs", auth_methods: %w[phone_password email_password])
      @user = User.create!
      BrandMembership.create!(brand: @brand, user: @user, status: :active)
      @phone = @user.identity_identifiers.create!(kind: :phone, normalized_value: "27821234567", verified_at: Time.current)
      @credential = @user.credentials.create!(identity_identifier: @phone, kind: :password, status: :active)
      Identity::PasswordEngine.set!(credential: @credential, password: "secret")
    end

    test "recovery enqueues delivery with only the challenge id after the code is committed" do
      assert_enqueued_with(job: Notifications::DeliverChallengeJob) do
        with_sms_provider("test") do
          Identity::RecoveryRequester.call(brand: @brand, identifier: "27821234567", ip_address: "203.0.113.5")
        end
      end

      challenge = OtpChallenge.password_recovery.last
      enqueued = enqueued_jobs.find { |job| job[:job] == Notifications::DeliverChallengeJob }
      assert_equal [ challenge.id ], enqueued[:args]
      # The committed challenge is durably visible to the worker...
      assert OtpChallenge.exists?(challenge.id)
      # ...and no argument carries the six-digit code.
      assert_no_match(/\b\d{6}\b/, enqueued[:args].join(","))
    end

    test "the delivery code is stored as ciphertext, not plaintext" do
      with_sms_provider("test") do
        Identity::RecoveryRequester.call(brand: @brand, identifier: "27821234567", ip_address: "203.0.113.5")
      end
      challenge = OtpChallenge.password_recovery.last

      raw = OtpChallenge.connection.select_value(
        "SELECT delivery_code FROM otp_challenges WHERE id = #{challenge.id.to_i}"
      )
      assert raw.present?
      assert_no_match(/\b\d{6}\b/, raw, "raw column must not contain the plaintext code")
      # Round-trips back to the plaintext through Active Record Encryption.
      assert_match(/\A\d{6}\z/, challenge.reload.delivery_code)
    end

    test "misconfigured provider fails closed synchronously and enqueues nothing" do
      assert_no_enqueued_jobs do
        with_sms_provider("required") do
          Identity::RecoveryRequester.call(brand: @brand, identifier: "27821234567", ip_address: "203.0.113.5")
        end
      end

      assert OtpChallenge.password_recovery.last.consumed?, "challenge is consumed when delivery cannot be attempted"
    end

    private

    def with_sms_provider(provider)
      previous = ENV["D8N_SMS_PROVIDER"]
      ENV["D8N_SMS_PROVIDER"] = provider
      yield
    ensure
      ENV["D8N_SMS_PROVIDER"] = previous
    end
  end
end
