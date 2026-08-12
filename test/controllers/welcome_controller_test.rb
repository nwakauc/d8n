require "test_helper"

class WelcomeControllerTest < ActionDispatch::IntegrationTest
  test "returns API welcome and planned services" do
    get root_url

    assert_response :success

    body = response.parsed_body
    assert_equal "Welcome to D8N API", body["message"]
    assert_equal "d8n", body["app"]
    assert_equal "v1", body["api_version"]
    assert_includes body["services"].map { |service| service["key"] }, "identity"
    assert_includes body["services"].map { |service| service["key"] }, "messaging"
    assert_includes body["services"].map { |service| service["key"] }, "billing"
  end
end
