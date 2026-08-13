require "test_helper"

class Api::DocsControllerTest < ActionDispatch::IntegrationTest
  test "serves self-hosted interactive API documentation" do
    host! "unknown.test"

    get "/api/docs"

    assert_response :success
    assert_includes response.media_type, "text/html"
    assert_includes response.body, "/api-docs/swagger-ui.css"
    assert_includes response.body, "/api-docs/swagger-ui-bundle.js"
    assert_includes response.body, "/api-docs/swagger-initializer.js"
    assert_no_match %r{https?://}, response.body
    assert_includes response.headers.fetch("Content-Security-Policy"), "connect-src 'self'"
    assert_equal "noindex, nofollow", response.headers.fetch("X-Robots-Tag")
  end

  test "configures Swagger UI from the canonical contract without persisting authorization" do
    initializer = Rails.root.join("public/api-docs/swagger-initializer.js").read

    assert_includes initializer, 'url: "/api/v1/openapi.json"'
    assert_includes initializer, "persistAuthorization: false"
    assert_includes initializer, "validatorUrl: null"
    assert Rails.root.join("public/api-docs/swagger-ui.css").exist?
    assert Rails.root.join("public/api-docs/swagger-ui-bundle.js").exist?
  end
end
