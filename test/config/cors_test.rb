require "test_helper"
require "yaml"

class CorsTest < ActionDispatch::IntegrationTest
  test "permits the HookUs development origin to preflight auth requests" do
    options "/api/v1/auth/password/register", headers: {
      "Origin" => "http://localhost:3001",
      "Access-Control-Request-Method" => "POST",
      "Access-Control-Request-Headers" => "content-type"
    }

    assert_response :ok
    assert_equal "http://localhost:3001", response.headers["Access-Control-Allow-Origin"]
    assert_includes response.headers.fetch("Access-Control-Allow-Methods"), "POST"
    assert_includes response.headers.fetch("Access-Control-Allow-Headers").downcase, "content-type"
  end

  test "permits authorization headers from the loopback development origin" do
    options "/api/v1/auth/methods", headers: {
      "Origin" => "http://127.0.0.1:3001",
      "Access-Control-Request-Method" => "GET",
      "Access-Control-Request-Headers" => "authorization"
    }

    assert_response :ok
    assert_equal "http://127.0.0.1:3001", response.headers["Access-Control-Allow-Origin"]
    assert_includes response.headers.fetch("Access-Control-Allow-Headers").downcase, "authorization"
  end

  test "does not grant cross-origin access to an unconfigured origin" do
    options "/api/v1/auth/methods", headers: {
      "Origin" => "https://attacker.example",
      "Access-Control-Request-Method" => "GET"
    }

    assert_nil response.headers["Access-Control-Allow-Origin"]
  end

  # Staging boots with RAILS_ENV=production, so the initializer's development
  # default origins do not apply there; the origins must be supplied explicitly
  # through D8N_CORS_ORIGINS in the Kamal env. These assertions guard the actual
  # deployed configuration that lets the local HookUs frontend reach staging.
  test "staging deploy config allows the HookUs development origin without a wildcard" do
    staging = YAML.safe_load_file(Rails.root.join("config/deploy.staging.yml"))
    origins = staging.fetch("env").fetch("clear").fetch("D8N_CORS_ORIGINS")

    permitted = origins.split(",").map(&:strip)

    assert_includes permitted, "http://localhost:3001"
    refute_includes permitted, "*", "staging CORS origins must never include a wildcard"
    assert(permitted.none? { |origin| origin.include?("*") },
      "staging CORS origins must not contain wildcard patterns")
  end
end
