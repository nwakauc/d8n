require "test_helper"

module Notifications
  module Push
    class ExpoGatewayTest < ActiveSupport::TestCase
      setup do
        @delivery = NotificationDelivery.new(id: 42)
      end

      test "sends the legacy Date9ja Expo payload and returns the ticket id" do
        captured = {}
        stub = lambda do |url, headers:, payload:|
          captured[:url] = url
          captured[:headers] = headers
          captured[:payload] = payload
          HttpClient::Response.new(status: 200, body: { data: [ { status: "ok", id: "ticket-42" } ] }.to_json)
        end

        response = stub_method(HttpClient, :post_json, stub) do
          ExpoGateway.deliver(
            token: "ExponentPushToken[device123]",
            title: "New message",
            body: "Hello",
            data: { notification_id: "notification-1" },
            delivery: @delivery,
            idempotency_key: "delivery-42"
          )
        end

        assert response.success?
        assert_equal "expo", response.provider
        assert_equal "ticket-42", response.external_id
        assert_equal "https://exp.host/--/api/v2/push/send", captured[:url]
        assert_equal "ExponentPushToken[device123]", captured[:payload][:to]
        assert_equal "default", captured[:payload][:sound]
        assert_equal({ notification_id: "notification-1" }, captured[:payload][:data])
        assert_empty captured[:headers]
      end

      test "maps an unregistered Expo token to D8N invalid_token" do
        response = stub_method(HttpClient, :post_json, ->(*, **) {
          HttpClient::Response.new(
            status: 200,
            body: { data: [ { status: "error", details: { error: "DeviceNotRegistered" } } ] }.to_json
          )
        }) do
          deliver
        end

        assert_not response.success?
        assert_not response.retryable
        assert_equal "invalid_token", response.error_code
      end

      test "retries Expo rate limits and provider outages" do
        [
          HttpClient::Response.new(status: 200, body: { data: [ { status: "error", details: { error: "MessageRateExceeded" } } ] }.to_json),
          HttpClient::Response.new(status: 503, body: "temporarily unavailable")
        ].each do |http_response|
          response = stub_method(HttpClient, :post_json, ->(*, **) { http_response }) { deliver }

          assert_not response.success?
          assert response.retryable
        end
      end

      test "does not expose provider details in permanent failures" do
        response = stub_method(HttpClient, :post_json, ->(*, **) {
          HttpClient::Response.new(status: 401, body: { error: "secret provider detail" }.to_json)
        }) { deliver }

        assert_not response.success?
        assert_equal "http_401", response.error_code
        assert_not_includes response.error_message, "secret provider detail"
      end

      test "can send an Expo access token without requiring one" do
        captured = {}
        stub = ->(_url, headers:, payload:) {
          captured[:headers] = headers
          HttpClient::Response.new(status: 200, body: { data: [ { status: "ok" } ] }.to_json)
        }

        with_env("D8N_EXPO_ACCESS_TOKEN" => "expo-secret") do
          stub_method(HttpClient, :post_json, stub) { deliver }
        end

        assert_equal "Bearer expo-secret", captured[:headers]["Authorization"]
      end

      private

      def deliver
        ExpoGateway.deliver(
          token: "ExponentPushToken[device123]", title: "Title", body: "Body", data: {},
          delivery: @delivery, idempotency_key: "delivery-42"
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
end
