require "test_helper"
require "yaml"

class KamalStagingR2ConfigurationTest < ActiveSupport::TestCase
  SECRET_LINE = /\A([A-Z0-9_]+)=\$([A-Z0-9_]+)\z/
  REQUIRED_APP_KEYS = %w[
    D8N_R2_ACCESS_KEY_ID
    D8N_R2_SECRET_ACCESS_KEY
    D8N_R2_BUCKET
    D8N_R2_ENDPOINT
  ].freeze

  test "staging destination enables R2 and declares the required keys as secret" do
    staging = YAML.safe_load_file(Rails.root.join("config/deploy.staging.yml"))
    env = staging.fetch("env")

    assert_equal "true", env.fetch("clear").fetch("D8N_R2_ENABLED")
    assert_equal REQUIRED_APP_KEYS.sort, env.fetch("secret").sort
  end

  test "staging secrets file maps each required key to a STAGING_R2_ env reference, never a literal value" do
    lines = Rails.root.join(".kamal/secrets.staging").readlines(chomp: true).reject(&:blank?)
    mapping = lines.filter_map do |line|
      match = SECRET_LINE.match(line)
      [ match[1], match[2] ] if match
    end.to_h

    REQUIRED_APP_KEYS.each do |app_key|
      local_env_name = mapping[app_key]
      assert local_env_name, "#{app_key} is not mapped from a $ENV_VAR reference in .kamal/secrets.staging"
      assert_equal "STAGING_R2_#{app_key.delete_prefix('D8N_R2_')}", local_env_name
    end
  end

  test "no line in the staging secrets file contains anything other than a KEY=$ENV_VAR reference" do
    lines = Rails.root.join(".kamal/secrets.staging").readlines(chomp: true)

    lines.each do |line|
      next if line.blank? || line.start_with?("#")

      assert_match SECRET_LINE, line, "expected a KEY=$ENV_VAR reference, found a possible literal value"
    end
  end

  test "the R2 storage service reads the same D8N_R2_ names the staging secrets file provides" do
    storage_config = Rails.root.join("config/storage.yml").read

    REQUIRED_APP_KEYS.each do |app_key|
      assert_includes storage_config, %(ENV["#{app_key}"]),
        "config/storage.yml's r2 service does not reference #{app_key}"
    end
    assert_match(/public:\s*false/, storage_config.split(/^r2:/).last.to_s.lines.take(8).join)
  end
end
