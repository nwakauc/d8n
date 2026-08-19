require "test_helper"

module Notifications
  module Sms
    class TwilioGatewayTest < ActiveSupport::TestCase
      setup do
        @brand = Brand.create!(slug: "hookus", name: "HookUs")
        @delivery = NotificationDelivery.create!(
          brand: @brand, channel: :sms, provider: "twilio", recipient: "27821234567", status: :pending
        )
      end

      test "is configured from API-key credentials and never requires the account auth token" do
        with_env(twilio_env) { assert TwilioGateway.configured? }
        # Missing API-key secret => not configured.
        with_env(twilio_env.merge("TWILIO_CLIENT_SECRET" => nil)) { assert_not TwilioGateway.configured? }
        # Missing API-key SID => not configured.
        with_env(twilio_env.merge("TWILIO_API_KEY_SID" => nil)) { assert_not TwilioGateway.configured? }
        # The legacy Account Auth Token is irrelevant to configuration.
        with_env(twilio_env.merge("TWILIO_AUTH_TOKEN" => nil)) { assert TwilioGateway.configured? }
      end

      test "authenticates with the API-key SID and secret, not the account auth token" do
        captured = {}
        stub = ->(_url, headers:, form:) {
          captured[:auth] = headers["Authorization"]
          captured[:form] = form
          HttpClient::Response.new(status: 201, body: { sid: "SM123" }.to_json)
        }
        response = with_env(twilio_env) { stub_method(HttpClient, :post_form, stub) { deliver } }

        assert response.success?
        assert_equal "SM123", response.external_id
        assert_equal "+27821234567", captured[:form]["To"]
        assert_equal "MG_hookus", captured[:form]["MessagingServiceSid"]
        assert captured[:auth].start_with?("Basic ")
        decoded = captured[:auth].delete_prefix("Basic ").unpack1("m")
        assert_equal "SKtest:secretvalue", decoded, "must authenticate with API key SID:secret"
      end

      test "already-prefixed numbers are not double-prefixed" do
        captured = {}
        stub = ->(_url, headers:, form:) { captured[:form] = form; HttpClient::Response.new(status: 201, body: { sid: "SM1" }.to_json) }
        with_env(twilio_env) do
          stub_method(HttpClient, :post_form, stub) do
            TwilioGateway.deliver(to: "+27821234567", body: "hi", brand: @brand, delivery: @delivery)
          end
        end

        assert_equal "+27821234567", captured[:form]["To"]
      end

      test "rate limiting and 5xx are transient/retryable" do
        [ 429, 500, 503 ].each do |status|
          response = with_env(twilio_env) do
            stub_method(HttpClient, :post_form, http_response(status, { code: 20_429, message: "slow down" })) { deliver }
          end
          assert response.retryable, "expected status #{status} to be retryable"
        end
      end

      test "invalid recipient (400) is permanent" do
        response = with_env(twilio_env) do
          stub_method(HttpClient, :post_form, http_response(400, { code: 21_211, message: "invalid To" })) { deliver }
        end

        assert_not response.success?
        assert_not response.retryable
        assert_equal "Twilio rejected the message", response.error_message
      end

      test "network error is a retryable transient" do
        raiser = ->(*_a, **_k) { raise HttpClient::TransientError, "SocketError" }
        response = with_env(twilio_env) { stub_method(HttpClient, :post_form, raiser) { deliver } }

        assert response.retryable
      end

      private

      def deliver
        TwilioGateway.deliver(to: "27821234567", body: "HookUs verification code: 123456", brand: @brand, delivery: @delivery)
      end

      def http_response(status, body)
        ->(_url, headers:, form:) { HttpClient::Response.new(status:, body: body.to_json) }
      end

      def twilio_env
        { "TWILIO_ACCOUNT_SID" => "AC1",
          "TWILIO_API_KEY_SID" => "SKtest",
          "TWILIO_CLIENT_SECRET" => "secretvalue",
          "TWILIO_HOOKUS_MESSAGING_SERVICE_SID" => "MG_hookus",
          "TWILIO_MESSAGING_SERVICE_SID" => nil,
          "TWILIO_FROM_NUMBER" => nil,
          "TWILIO_AUTH_TOKEN" => nil }
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
