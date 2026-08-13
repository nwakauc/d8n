require "test_helper"
require "yaml"

class OpenapiContractTest < ActionDispatch::IntegrationTest
  CONTRACT_PATH = Rails.root.join("docs/api/openapi.yaml")
  HTTP_METHODS = %w[get post put patch delete].freeze

  test "documents every API v1 route exactly once" do
    assert_equal routed_operations, documented_operations
    assert_equal operation_ids.uniq, operation_ids
  end

  test "contains only valid local component references" do
    references(contract).each do |reference|
      assert reference.start_with?("#/"), "external OpenAPI reference is not allowed: #{reference}"
      assert reference.split("/").drop(1).reduce(contract) { |node, key| node.fetch(key) }
    end
  end

  test "publishes the canonical contract as JSON" do
    host! "unknown.test"

    get "/api/v1/openapi.json"

    assert_response :success
    runtime_contract = JSON.parse(response.body)
    assert_equal contract.fetch("info"), runtime_contract.fetch("info")
    assert_equal contract.fetch("servers"), runtime_contract.fetch("servers")
    assert_match(/public/, response.headers.fetch("Cache-Control"))
  end

  test "uses the current origin for self-hosted interactive documentation" do
    current_origin = contract.fetch("servers").first

    assert_equal "/", current_origin.fetch("url")
    assert_match(/Swagger UI/, current_origin.fetch("description"))
  end

  private

  def contract
    @contract ||= YAML.safe_load_file(CONTRACT_PATH, aliases: false)
  end

  def documented_operations
    contract.fetch("paths").flat_map do |path, operations|
      operations.filter_map do |method, operation|
        [ method.upcase, path ] if HTTP_METHODS.include?(method) && operation.is_a?(Hash)
      end
    end.sort
  end

  def routed_operations
    Rails.application.routes.routes.filter_map do |route|
      controller = route.defaults[:controller].to_s
      next unless controller.start_with?("api/v1/")

      path = route.path.spec.to_s.sub("(.:format)", "").gsub(/:([a-z_]+)/, '{\\1}')
      [ route.verb, path ]
    end.sort
  end

  def operation_ids
    contract.fetch("paths").values.flat_map do |operations|
      operations.filter_map { |method, operation| operation["operationId"] if HTTP_METHODS.include?(method) }
    end
  end

  def references(value)
    case value
    when Hash
      value.flat_map { |key, child| key == "$ref" ? child : references(child) }
    when Array
      value.flat_map { |child| references(child) }
    else
      []
    end
  end
end
