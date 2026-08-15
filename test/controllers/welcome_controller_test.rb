require "test_helper"

class WelcomeControllerTest < ActionDispatch::IntegrationTest
  test "returns API welcome and planned services" do
    get root_url

    assert_response :success

    body = response.parsed_body
    assert_equal "Welcome to D8N API", body["message"]
    assert_equal "d8n", body["app"]
    assert_equal "v1", body["api_version"]
    assert_nil body["current_brand"]
    services = body["services"].index_by { |service| service["key"] }
    assert_includes services.keys, "identity"
    assert_includes services.keys, "messaging"
    assert_includes services.keys, "billing"

    # Delivery status must reflect what is actually implemented today.
    assert_equal "available", services.fetch("identity")["status"]
    assert_equal "available", services.fetch("matching")["status"]
    assert_equal "preview", services.fetch("messaging")["status"]
    # Owner-scoped profile-photo upload/retrieval is live on private R2.
    assert_equal "preview", services.fetch("media")["status"]
    assert_equal "planned", services.fetch("billing")["status"]

    assert_includes body["status_legend"].keys, "available"
    assert_includes body["status_legend"].keys, "planned"
  end

  test "includes current brand when host resolves" do
    brand = Brand.create!(slug: "hookus", name: "HookUs")
    BrandDomain.create!(brand:, host: "hookus.example")

    host! "hookus.example"
    get root_url

    assert_response :success

    current_brand = response.parsed_body["current_brand"]
    assert_equal "hookus", current_brand["slug"]
    assert_equal "HookUs", current_brand["name"]
  end
end
