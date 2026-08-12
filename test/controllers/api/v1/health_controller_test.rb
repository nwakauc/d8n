require "test_helper"

class Api::V1::HealthControllerTest < ActionDispatch::IntegrationTest
  test "returns health status" do
    get api_v1_health_url

    assert_response :success

    body = response.parsed_body
    assert_equal "ok", body["status"]
    assert_equal "d8n", body["app"]
    assert_equal "v1", body["api_version"]
  end
end
