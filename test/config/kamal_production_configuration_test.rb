require "test_helper"
require "yaml"

class KamalProductionConfigurationTest < ActiveSupport::TestCase
  test "production proxy serves the HookUs and DateZA hosts with TLS" do
    production = YAML.safe_load_file(Rails.root.join("config/deploy.production.yml"))

    assert_equal true, production.dig("proxy", "ssl")
    assert_equal(
      %w[ api.d8n.tech dateza-api.d8n.tech ],
      production.dig("proxy", "hosts")
    )
  end

  test "DATEZA_API_HOST matches the DateZA proxy host so BrandDomain resolution cannot drift" do
    production = YAML.safe_load_file(Rails.root.join("config/deploy.production.yml"))
    proxy_hosts = production.dig("proxy", "hosts")
    dateza_proxy_host = proxy_hosts.find { |host| host.include?("dateza") }

    dateza_api_host = production.dig("env", "clear", "DATEZA_API_HOST")

    assert_equal dateza_proxy_host, dateza_api_host,
      "DATEZA_API_HOST must match the DateZA proxy host, or brands:install_dateza " \
      "will map the wrong hostname to the dateza Brand and DateZA auth will 404 in production"
  end

  test "production CORS origins include both DateZA host forms" do
    production = YAML.safe_load_file(Rails.root.join("config/deploy.production.yml"))
    origins = production.dig("env", "clear", "D8N_CORS_ORIGINS").split(",")

    assert_includes origins, "https://www.date-za.com"
    assert_includes origins, "https://date-za.com"
  end
end
