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

  test "permits the DateZA development origin with cookie credentials and CSRF headers" do
    options "/api/v1/auth/methods", headers: {
      "Origin" => "http://localhost:5173",
      "Access-Control-Request-Method" => "GET",
      "Access-Control-Request-Headers" => "authorization,x-csrf-token"
    }

    assert_response :ok
    assert_equal "http://localhost:5173", response.headers["Access-Control-Allow-Origin"]
    assert_includes response.headers.fetch("Access-Control-Allow-Headers").downcase, "authorization"
    assert_includes response.headers.fetch("Access-Control-Allow-Headers").downcase, "x-csrf-token"
    assert_equal "true", response.headers["Access-Control-Allow-Credentials"]
  end

  test "permits the deployed DateZA origin with cookie credentials" do
    options "/api/v1/auth/methods", headers: {
      "Origin" => "https://dateza.vercel.app",
      "Access-Control-Request-Method" => "GET",
      "Access-Control-Request-Headers" => "authorization"
    }

    assert_response :ok
    assert_equal "https://dateza.vercel.app", response.headers["Access-Control-Allow-Origin"]
    assert_includes response.headers.fetch("Access-Control-Allow-Headers").downcase, "authorization"
    assert_equal "true", response.headers["Access-Control-Allow-Credentials"]
  end

  test "permits the deployed Date9ja staging frontend origin with cookie credentials" do
    options "/api/v1/auth/methods", headers: {
      "Origin" => "https://date9ja-seo-frontend.vercel.app",
      "Access-Control-Request-Method" => "GET",
      "Access-Control-Request-Headers" => "authorization"
    }

    assert_response :ok
    assert_equal "https://date9ja-seo-frontend.vercel.app", response.headers["Access-Control-Allow-Origin"]
    assert_includes response.headers.fetch("Access-Control-Allow-Headers").downcase, "authorization"
    assert_equal "true", response.headers["Access-Control-Allow-Credentials"]
  end

  test "does not grant access to an arbitrary/preview Vercel origin" do
    [ "https://date9ja-seo-frontend-git-preview-uc.vercel.app", "https://random-app.vercel.app" ].each do |origin|
      options "/api/v1/auth/methods", headers: { "Origin" => origin, "Access-Control-Request-Method" => "GET" }
      assert_nil response.headers["Access-Control-Allow-Origin"], "must not permit #{origin}"
    end
  end

  test "permits the Date9ja development origin to upload directly to local disk storage" do
    options "/rails/active_storage/disk/signed-upload-token", headers: {
      "Origin" => "http://localhost:3200",
      "Access-Control-Request-Method" => "PUT",
      "Access-Control-Request-Headers" => "content-type,content-md5"
    }

    assert_response :ok
    assert_equal "http://localhost:3200", response.headers["Access-Control-Allow-Origin"]
    assert_includes response.headers.fetch("Access-Control-Allow-Methods"), "PUT"
    assert_includes response.headers.fetch("Access-Control-Allow-Headers").downcase, "content-type"
    assert_includes response.headers.fetch("Access-Control-Allow-Headers").downcase, "content-md5"
    assert_nil response.headers["Access-Control-Allow-Credentials"]
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
  # deployed configuration that lets approved HookUs and DateZA frontends reach
  # staging.
  test "staging deploy config allows approved frontend origins without a wildcard" do
    staging = YAML.safe_load_file(Rails.root.join("config/deploy.staging.yml"))
    origins = staging.fetch("env").fetch("clear").fetch("D8N_CORS_ORIGINS")

    permitted = origins.split(",").map(&:strip)

    assert_includes permitted, "http://localhost:3001"
    assert_includes permitted, "http://localhost:5173"
    assert_includes permitted, "https://dateza.vercel.app"
    assert_includes permitted, "https://date9ja-seo-frontend.vercel.app"
    refute_includes permitted, "*", "staging CORS origins must never include a wildcard"
    assert(permitted.none? { |origin| origin.include?("*") },
      "staging CORS origins must not contain wildcard patterns")
  end

  test "staging deploy config maps a dedicated Date9ja host, distinct from production" do
    staging = YAML.safe_load_file(Rails.root.join("config/deploy.staging.yml"))
    env = staging.fetch("env").fetch("clear")

    assert_includes staging.fetch("proxy").fetch("hosts"), "date9ja-staging-api.d8n.tech"
    assert_equal "date9ja-staging-api.d8n.tech", env.fetch("DATE9JA_API_HOST")
  end

  # Pre-cutover exception, explicitly authorized: the Vercel acceptance
  # frontend is deliberately granted CORS access to the real production
  # backend for founder acceptance testing tonight, but only against the
  # temporary date9ja-api.d8n.tech host (see config/deploy.production.yml) --
  # never against date9ja.love, whose DNS/routing stays untouched. Remove
  # this origin once api.date9ja.love is the live cutover host and the
  # Vercel frontend is reconfigured to call it directly.
  test "production deploy config grants the Vercel acceptance frontend CORS access for founder testing, alongside the canonical Date9ja frontend" do
    production = YAML.safe_load_file(Rails.root.join("config/deploy.production.yml"))
    origins = production.fetch("env").fetch("clear").fetch("D8N_CORS_ORIGINS").split(",").map(&:strip)

    assert_includes origins, "https://www.date9ja.love"
    assert_includes origins, "https://date9ja-seo-frontend.vercel.app"
    assert(origins.none? { |origin| origin.include?("*") },
      "production CORS origins must not contain wildcard patterns")
  end
end
