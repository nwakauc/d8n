require "test_helper"

module Notifications
  module Email
    class ResendGatewayTest < ActiveSupport::TestCase
      setup do
        @brand = Brand.create!(slug: "hookus", name: "HookUs")
        @delivery = NotificationDelivery.create!(
          brand: @brand, channel: :email, provider: "resend", recipient: "ada@example.com", status: :pending
        )
      end

      test "is configured only when api key and from address are both present" do
        with_env("RESEND_API_KEY" => nil, "D8N_EMAIL_FROM" => nil) { assert_not ResendGateway.configured? }
        with_env("RESEND_API_KEY" => "re_x", "D8N_EMAIL_FROM" => nil) { assert_not ResendGateway.configured? }
        with_env("RESEND_API_KEY" => nil, "D8N_EMAIL_FROM" => "HookUs <no-reply@hookus.test>") { assert_not ResendGateway.configured? }
        with_env("RESEND_API_KEY" => "re_x", "D8N_EMAIL_FROM" => "HookUs <no-reply@hookus.test>") { assert ResendGateway.configured? }
      end

      test "successful send returns provider message id" do
        captured = {}
        stub = ->(_url, headers:, payload:) {
          captured[:headers] = headers
          captured[:payload] = payload
          HttpClient::Response.new(status: 200, body: { id: "email_123" }.to_json)
        }
        response = with_env(resend_env) do
          stub_method(HttpClient, :post_json, stub) { deliver(idempotency_key: "otp-challenge-42") }
        end

        assert response.success?
        assert_equal "resend", response.provider
        assert_equal "email_123", response.external_id
        assert_equal "Bearer re_secret", captured[:headers]["Authorization"]
        assert_equal "otp-challenge-42", captured[:headers]["Idempotency-Key"]
        assert_equal [ "ada@example.com" ], captured[:payload][:to]
        assert captured[:payload][:subject].present?
      end

      test "auth failure is permanent and leaks no provider detail" do
        response = with_env(resend_env) do
          stub_method(HttpClient, :post_json, http_response(401, { name: "unauthorized", message: "bad key" })) { deliver }
        end

        assert_not response.success?
        assert_not response.retryable
        assert_equal "Resend rejected the email", response.error_message
        assert_not_includes response.error_message, "bad key"
      end

      test "server error is transient and retryable" do
        response = with_env(resend_env) do
          stub_method(HttpClient, :post_json, http_response(503, { name: "internal", message: "oops" })) { deliver }
        end

        assert_not response.success?
        assert response.retryable
      end

      test "invalid recipient (422) is permanent, not retryable" do
        response = with_env(resend_env) do
          stub_method(HttpClient, :post_json, http_response(422, { name: "validation_error", message: "bad to" })) { deliver }
        end

        assert_not response.success?
        assert_not response.retryable
      end

      test "network error surfaces as retryable transient" do
        raiser = ->(*_args, **_kw) { raise HttpClient::TransientError, "Timeout::Error" }
        response = with_env(resend_env) do
          stub_method(HttpClient, :post_json, raiser) { deliver }
        end

        assert_not response.success?
        assert response.retryable
      end

      test "reports not configured without sending" do
        response = with_env("RESEND_API_KEY" => nil, "D8N_EMAIL_FROM" => nil) do
          stub_method(HttpClient, :post_json, ->(*_a, **_k) { flip("provider must not be called") }) { deliver }
        end

        assert_not response.success?
        assert_equal "provider_not_configured", response.error_code
      end

      private

      def deliver(idempotency_key: nil)
        ResendGateway.deliver(
          brand: @brand, recipient: "ada@example.com", code: "123456",
          mailer_action: :verification_code, delivery: @delivery, idempotency_key:
        )
      end

      def http_response(status, body)
        ->(_url, headers:, payload:) { HttpClient::Response.new(status:, body: body.to_json) }
      end

      def resend_env
        { "RESEND_API_KEY" => "re_secret", "D8N_EMAIL_FROM" => "HookUs <no-reply@hookus.test>" }
      end

      def flip(message)
        raise Minitest::Assertion, message
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
end
