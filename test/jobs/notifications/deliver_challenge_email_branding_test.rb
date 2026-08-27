require "test_helper"

module Notifications
  class DeliverChallengeEmailBrandingTest < ActiveJob::TestCase
    setup do
      Email::TestGateway.clear
    end

    test "a persisted DateZA verification challenge keeps DateZA branding in background delivery" do
      dateza = Brand.create!(slug: "dateza", name: "DateZA")
      challenge = create_email_challenge(brand: dateza, recipient: "dateza@example.com")

      with_env(
        "D8N_EMAIL_PROVIDER" => "test",
        "D8N_EMAIL_FROM" => "HookUs <no-reply@hookus.app>",
        "D8N_DATEZA_EMAIL_FROM" => "DateZA <no-reply@date-za.com>"
      ) do
        DeliverChallengeJob.perform_now(challenge.id)
      end

      message = Email::TestGateway.deliveries.sole
      assert_equal "Verify your DateZA email", message.fetch(:subject)
      assert_equal "DateZA <no-reply@date-za.com>", message.fetch(:from)
      assert_includes message.fetch(:html), "DateZA heart logo"
      assert_includes message.fetch(:html), "#E8375A"
      assert_includes message.fetch(:html), "Verify your email"
      assert_includes message.fetch(:html), "123456"
      assert_includes message.fetch(:html), "max-width: 600px"
      assert_includes message.fetch(:text), "Use this code to verify your DateZA account."
      assert_includes message.fetch(:text), "123456"
      assert_includes message.fetch(:text), "This code expires in 60 minutes."
      assert_not_includes message.to_json, "HookUs"
      assert_nil challenge.reload.delivery_code
    end

    test "a persisted HookUs verification challenge keeps the existing HookUs mail" do
      hookus = Brand.create!(slug: "hookus", name: "HookUs")
      challenge = create_email_challenge(brand: hookus, recipient: "hookus@example.com")

      with_env(
        "D8N_EMAIL_PROVIDER" => "test",
        "D8N_EMAIL_FROM" => "HookUs <no-reply@hookus.app>",
        "D8N_HOOKUS_EMAIL_FROM" => nil
      ) do
        DeliverChallengeJob.perform_now(challenge.id)
      end

      message = Email::TestGateway.deliveries.sole
      assert_equal "Verify your HookUs email", message.fetch(:subject)
      assert_equal "HookUs <no-reply@hookus.app>", message.fetch(:from)
      assert_includes message.fetch(:html), "Your HookUs verification code"
      assert_includes message.fetch(:text), "Your HookUs verification code"
      assert_not_includes message.fetch(:html), "DateZA heart logo"
      assert_nil challenge.reload.delivery_code
    end

    test "a HookUs email-change challenge uses generic HookUs copy and the proposed recipient" do
      hookus = Brand.create!(slug: "hookus", name: "HookUs")
      challenge = create_email_challenge(brand: hookus, recipient: "old@example.com")
      challenge.update!(
        kind: :email_change,
        identifier: "new@example.com",
        metadata: { purpose: "email_change", session_id: 123 }
      )

      with_env(
        "D8N_EMAIL_PROVIDER" => "test",
        "D8N_EMAIL_FROM" => "HookUs <no-reply@hookus.app>"
      ) do
        DeliverChallengeJob.perform_now(challenge.id)
      end

      message = Email::TestGateway.deliveries.sole
      assert_equal "Confirm your new HookUs email", message.fetch(:subject)
      assert_equal "new@example.com", message.fetch(:to)
      assert_includes message.fetch(:text), "confirm your new HookUs email address"
      assert_not_includes message.fetch(:html), "DateZA heart logo"
      assert_not_includes message.to_json, "old@example.com"
    end

    private

    def create_email_challenge(brand:, recipient:)
      user = User.create!
      BrandMembership.create!(brand:, user:, status: :active)
      identifier = user.identity_identifiers.create!(kind: :email, normalized_value: recipient)
      code = "123456"

      OtpChallenge.create!(
        brand:,
        identity_identifier: identifier,
        kind: :email_verification,
        identifier: recipient,
        code_digest: OtpChallenge.digest_code(code),
        delivery_code: code,
        expires_at: 10.minutes.from_now,
        metadata: { purpose: "identifier_verification" }
      )
    end

    def with_env(overrides)
      previous = overrides.keys.index_with { |key| ENV[key] }
      overrides.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
      yield
    ensure
      previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    end
  end
end
