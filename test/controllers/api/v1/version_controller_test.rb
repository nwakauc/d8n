require "test_helper"

class Api::V1::VersionControllerTest < ActionDispatch::IntegrationTest
  test "returns non-secret release identity without requiring a brand" do
    previous = {
      "D8N_GIT_SHA" => ENV["D8N_GIT_SHA"],
      "KAMAL_VERSION" => ENV["KAMAL_VERSION"],
      "D8N_DEPLOYMENT_ENV" => ENV["D8N_DEPLOYMENT_ENV"],
      "D8N_BUILD_TIMESTAMP" => ENV["D8N_BUILD_TIMESTAMP"]
    }
    ENV.update(
      "D8N_GIT_SHA" => "a" * 40,
      "KAMAL_VERSION" => "production-aabbccdd",
      "D8N_DEPLOYMENT_ENV" => "staging",
      "D8N_BUILD_TIMESTAMP" => "2026-08-29T12:00:00Z"
    )

    get "/api/v1/version", headers: { "Host" => "unknown.test" }

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "a" * 40, body.fetch("git_sha")
    assert_equal "production-aabbccdd", body.fetch("release")
    assert_equal "staging", body.fetch("environment")
    assert_equal "2026-08-29T12:00:00Z", body.fetch("build_timestamp")
    assert_no_match(/key|password|secret|token/i, body.keys.join(" "))
  ensure
    previous&.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end
