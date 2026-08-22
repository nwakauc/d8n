require "test_helper"
require "yaml"

class KamalStagingR2ConfigurationTest < ActiveSupport::TestCase
  SECRET_LINE = /\A([A-Z0-9_]+)=\$([A-Z0-9_]+)\z/

  BASE_APP_KEYS = %w[
    RAILS_MASTER_KEY
    D8N_DATABASE_PASSWORD
  ].freeze

  LEGACY_R2_APP_KEYS = %w[
    D8N_R2_ACCESS_KEY_ID
    D8N_R2_SECRET_ACCESS_KEY
    D8N_R2_BUCKET
    D8N_R2_ENDPOINT
  ].freeze

  BRAND_R2_APP_KEYS = %w[
    D8N_R2_HOOKUS_STAGING_ACCESS_KEY_ID
    D8N_R2_HOOKUS_STAGING_SECRET_ACCESS_KEY
    D8N_R2_HOOKUS_STAGING_BUCKET
    D8N_R2_DATEZA_STAGING_ACCESS_KEY_ID
    D8N_R2_DATEZA_STAGING_SECRET_ACCESS_KEY
    D8N_R2_DATEZA_STAGING_BUCKET
  ].freeze

  REQUIRED_APP_KEYS = (BASE_APP_KEYS + LEGACY_R2_APP_KEYS + BRAND_R2_APP_KEYS).freeze

  test "staging destination enables R2 and preserves all required app secrets" do
    staging = YAML.safe_load_file(Rails.root.join("config/deploy.staging.yml"))
    env = staging.fetch("env")
    secrets = env.fetch("secret")

    assert_equal "true", env.fetch("clear").fetch("D8N_R2_ENABLED")
    assert_equal "staging", env.fetch("clear").fetch("D8N_DEPLOYMENT_ENV")
    assert_equal %w[ hookus dateza ], env.fetch("clear").fetch("D8N_R2_BRANDS").split(",")

    REQUIRED_APP_KEYS.each do |key|
      assert_includes secrets, key
    end
  end

  test "staging secrets file maps base and R2 keys from environment references" do
    lines = Rails.root.join(".kamal/secrets.staging").readlines(chomp: true).reject(&:blank?)

    mapping = lines.filter_map do |line|
      match = SECRET_LINE.match(line)
      [ match[1], match[2] ] if match
    end.to_h

    assert_equal "RAILS_MASTER_KEY", mapping.fetch("RAILS_MASTER_KEY")
    assert_equal "D8N_DATABASE_PASSWORD", mapping.fetch("D8N_DATABASE_PASSWORD")

    LEGACY_R2_APP_KEYS.each do |app_key|
      expected_local_name = "STAGING_R2_#{app_key.delete_prefix('D8N_R2_')}"

      assert_equal expected_local_name, mapping.fetch(app_key)
    end

    assert_equal "STAGING_R2_ACCESS_KEY_ID", mapping.fetch("D8N_R2_HOOKUS_STAGING_ACCESS_KEY_ID")
    assert_equal "STAGING_R2_SECRET_ACCESS_KEY", mapping.fetch("D8N_R2_HOOKUS_STAGING_SECRET_ACCESS_KEY")
    assert_equal "STAGING_R2_BUCKET", mapping.fetch("D8N_R2_HOOKUS_STAGING_BUCKET")
    assert_equal "STAGING_DATEZA_R2_ACCESS_KEY_ID", mapping.fetch("D8N_R2_DATEZA_STAGING_ACCESS_KEY_ID")
    assert_equal "STAGING_DATEZA_R2_SECRET_ACCESS_KEY", mapping.fetch("D8N_R2_DATEZA_STAGING_SECRET_ACCESS_KEY")
    assert_equal "STAGING_DATEZA_R2_BUCKET", mapping.fetch("D8N_R2_DATEZA_STAGING_BUCKET")
  end

  test "no line in the staging secrets file contains anything other than a KEY=$ENV_VAR reference" do
    lines = Rails.root.join(".kamal/secrets.staging").readlines(chomp: true)

    lines.each do |line|
      next if line.blank? || line.start_with?("#")

      assert_match SECRET_LINE, line,
        "expected a KEY=$ENV_VAR reference, found a possible literal value"
    end
  end

  test "the R2 storage service reads the R2 secret names and remains private" do
    storage_config = Rails.root.join("config/storage.yml").read

    (LEGACY_R2_APP_KEYS + BRAND_R2_APP_KEYS).each do |app_key|
      assert_includes storage_config, %(ENV["#{app_key}"]),
        "config/storage.yml does not reference #{app_key}"
    end

    %w[ r2 r2_hookus_staging r2_dateza_staging r2_hookus_production r2_dateza_production ].each do |service|
      service_config = storage_config.split(/^#{service}:/).last.to_s.lines.take(12).join
      assert_match(/public:\s*false/, service_config, "#{service} must remain private")
    end
  end
end
