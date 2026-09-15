require "test_helper"

# Regression test for a real production incident (2026-09-15): once
# D8N_ALLOWED_HOSTS restricts config.hosts, kamal-proxy's internal health
# check -- which hits the container by its own Docker hostname, never a
# registered proxy host -- gets blocked by HostAuthorization and every deploy
# fails its own healthy-container check before ever going live. Exercises the
# exact middleware config/environments/production.rb builds, without booting
# RAILS_ENV=production.
class ProductionHostAuthorizationTest < ActiveSupport::TestCase
  def build_middleware
    app = ->(_env) { [ 200, {}, [ "ok" ] ] }
    ActionDispatch::HostAuthorization.new(
      app, %w[ api.d8n.tech dateza-api.d8n.tech ],
      exclude: ->(request) { request.path == "/up" }
    )
  end

  test "/up is served regardless of Host header, even one restricted by config.hosts" do
    response = Rack::MockRequest.new(build_middleware).get("/up", "HTTP_HOST" => "f4dd4798e751:80")

    assert_equal 200, response.status
  end

  test "an unlisted Host is still blocked for every other path" do
    response = Rack::MockRequest.new(build_middleware).get("/api/v1/me", "HTTP_HOST" => "f4dd4798e751:80")

    assert_equal 403, response.status
  end

  test "an allowlisted Host still reaches non-/up paths" do
    response = Rack::MockRequest.new(build_middleware).get("/api/v1/me", "HTTP_HOST" => "api.d8n.tech")

    assert_equal 200, response.status
  end
end
