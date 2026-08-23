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
        stub_method(Rails.env, :production?, -> { true }) do
          with_env("RESEND_API_KEY" => nil, "D8N_EMAIL_FROM" => nil, "D8N_HOOKUS_EMAIL_FROM" => nil) do
            assert_not ResendGateway.configured?(brand: @brand)
          end
          with_env("RESEND_API_KEY" => "re_x", "D8N_EMAIL_FROM" => nil, "D8N_HOOKUS_EMAIL_FROM" => nil) do
            assert_not ResendGateway.configured?(brand: @brand)
          end
          with_env("RESEND_API_KEY" => nil, "D8N_EMAIL_FROM" => "HookUs <no-reply@hookus.test>") do
            assert_not ResendGateway.configured?(brand: @brand)
          end
          with_env("RESEND_API_KEY" => "re_x", "D8N_EMAIL_FROM" => "HookUs <no-reply@hookus.test>") do
            assert ResendGateway.configured?(brand: @brand)
          end
        end
      end

      test "a non-HookUs brand never inherits the legacy HookUs sender" do
        dateza = Brand.create!(slug: "dateza", name: "DateZA")

        with_env(
          "RESEND_API_KEY" => "re_x",
          "D8N_EMAIL_FROM" => "HookUs <no-reply@hookus.test>",
          "D8N_DATEZA_EMAIL_FROM" => nil
        ) do
          assert_equal "DateZA <no-reply@dateza.test>", Email.from_address(dateza)
          assert_not_includes Email.from_address(dateza), "HookUs"
        end
      end

      test "an unconfigured production brand fails closed despite the legacy HookUs sender" do
        dateza = Brand.create!(slug: "dateza", name: "DateZA")

        with_env(
          "RESEND_API_KEY" => "re_x",
          "D8N_EMAIL_FROM" => "HookUs <no-reply@hookus.test>",
          "D8N_DATEZA_EMAIL_FROM" => nil
        ) do
          stub_method(Rails.env, :production?, -> { true }) do
            assert_nil Email.from_address(dateza)
            assert_not ResendGateway.configured?(brand: dateza)
          end
        end
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
        assert_equal "HookUs <no-reply@hookus.test>", captured[:payload][:from]
        assert_equal [ "ada@example.com" ], captured[:payload][:to]
        assert captured[:payload][:subject].present?
      end

      test "DateZA send uses its own Resend sender and rendered branding" do
        dateza = Brand.create!(slug: "dateza", name: "DateZA")
        captured = {}
        stub = ->(_url, headers:, payload:) {
          captured[:payload] = payload
          HttpClient::Response.new(status: 200, body: { id: "email_dateza" }.to_json)
        }

        response = with_env(
          "RESEND_API_KEY" => "re_secret",
          "D8N_EMAIL_FROM" => "HookUs <no-reply@hookus.test>",
          "D8N_DATEZA_EMAIL_FROM" => "DateZA <no-reply@date-za.com>"
        ) do
          stub_method(HttpClient, :post_json, stub) do
            deliver(brand: dateza, idempotency_key: "otp-challenge-dateza")
          end
        end

        assert response.success?
        assert_equal "DateZA <no-reply@date-za.com>", captured[:payload][:from]
        assert_equal "Verify your DateZA email", captured[:payload][:subject]
        assert_includes captured[:payload][:html], "Your DateZA verification code"
        assert_not_includes captured[:payload].to_json, "HookUs"
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

      def deliver(brand: @brand, idempotency_key: nil)
        ResendGateway.deliver(
          brand:, recipient: "ada@example.com", code: "123456",
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
