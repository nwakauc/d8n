require "test_helper"
require "yaml"

class KamalProductionConfigurationTest < ActiveSupport::TestCase
  test "production proxy serves every production brand host with TLS" do
    production = YAML.safe_load_file(Rails.root.join("config/deploy.production.yml"))

    assert_equal true, production.dig("proxy", "ssl")
    assert_equal(
      %w[ api.d8n.tech dateza-api.d8n.tech api.date9ja.love ],
      production.dig("proxy", "hosts")
    )
  end


  test "DATE9JA_API_HOST matches the canonical Date9ja proxy host and explicit Host allowlist" do
    production = YAML.safe_load_file(Rails.root.join("config/deploy.production.yml"))
    proxy_hosts = production.dig("proxy", "hosts")
    clear = production.dig("env", "clear")

    assert_equal "api.date9ja.love", clear.fetch("DATE9JA_API_HOST")
    assert_includes proxy_hosts, clear.fetch("DATE9JA_API_HOST")
    assert_includes clear.fetch("D8N_ALLOWED_HOSTS").split(","), clear.fetch("DATE9JA_API_HOST")
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

  test "production CORS explicitly permits the canonical Date9ja frontend without wildcards" do
    production = YAML.safe_load_file(Rails.root.join("config/deploy.production.yml"))
    origins = production.dig("env", "clear", "D8N_CORS_ORIGINS").split(",")

    assert_includes origins, "https://www.date9ja.love"
    assert origins.none? { |origin| origin.include?("*") }
  end

  test "production declares complete Date9ja R2, email and application URL wiring" do
    production = YAML.safe_load_file(Rails.root.join("config/deploy.production.yml"))
    clear = production.dig("env", "clear")
    secrets = production.dig("env", "secret")

    assert_includes clear.fetch("D8N_R2_BRANDS").split(","), "date9ja"
    assert_equal "resend", clear.fetch("D8N_EMAIL_PROVIDER")
    assert_equal "Date9ja <no-reply@date9ja.love>", clear.fetch("D8N_DATE9JA_EMAIL_FROM")
    assert_equal "https://www.date9ja.love", clear.fetch("D8N_DATE9JA_APP_URL")
    %w[ ACCESS_KEY_ID SECRET_ACCESS_KEY BUCKET ].each do |suffix|
      assert_includes secrets, "D8N_R2_DATE9JA_PRODUCTION_#{suffix}"
    end
    refute_includes secrets, "TWILIO_DATE9JA_MESSAGING_SERVICE_SID"
  end
end
