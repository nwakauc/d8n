require "test_helper"

class Api::V1::HealthControllerTest < ActionDispatch::IntegrationTest
  test "returns health status" do
    get api_v1_health_url

    assert_response :success

    body = response.parsed_body
    assert_equal "ok", body["status"]
    assert_equal "d8n", body["app"]
    assert_equal "v1", body["api_version"]
    assert_equal "ok", body.dig("checks", "primary_database")
    assert_equal "ok", body.dig("checks", "queue_database")
  end

  test "does not require a brand host" do
    host! "unknown.example"

    get api_v1_health_url

    assert_response :success
  end

  test "returns a bounded unavailable response when a dependency is down" do
    result = Infrastructure::Readiness::Result.new(
      ready?: false,
      checks: { primary_database: "ok", queue_database: "unavailable" },
      failed_dependencies: [ :queue_database ]
    )

    original_call = Infrastructure::Readiness.method(:call)
    begin
      Infrastructure::Readiness.define_singleton_method(:call) { result }
      get api_v1_health_url
    ensure
      Infrastructure::Readiness.define_singleton_method(:call, original_call)
    end

    assert_response :service_unavailable
    assert_equal(
      {
        "status" => "degraded",
        "app" => "d8n",
        "api_version" => "v1",
        "checks" => {
          "primary_database" => "ok",
          "queue_database" => "unavailable"
        }
      },
      response.parsed_body
    )
  end
end
