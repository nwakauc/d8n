require "test_helper"
require "yaml"

class KamalProductionR2SecretsTest < ActiveSupport::TestCase
  SECRET_LINE = /\A([A-Z0-9_]+)=\$([A-Z0-9_]+)\z/

  test "every secret declared in deploy.production.yml has a KEY=$ENV_VAR mapping, never a literal value" do
    production = YAML.safe_load_file(Rails.root.join("config/deploy.production.yml"))
    declared = production.dig("env", "secret")
    lines = Rails.root.join(".kamal/secrets.production").readlines(chomp: true)

    mapping = lines.filter_map do |line|
      next if line.blank? || line.start_with?("#")

      match = SECRET_LINE.match(line)
      assert match, "expected a KEY=$ENV_VAR reference, found a possible literal value: #{line.inspect}"
      [ match[1], match[2] ]
    end.to_h

    declared.each { |key| assert_includes mapping.keys, key, "#{key} is declared in deploy.production.yml but not mapped in .kamal/secrets.production" }
  end

  test "Date9ja production R2 secrets resolve to an existing bucket's credentials, distinct from DateZA's" do
    lines = Rails.root.join(".kamal/secrets.production").readlines(chomp: true)
    mapping = lines.filter_map do |line|
      match = SECRET_LINE.match(line)
      [ match[1], match[2] ] if match
    end.to_h

    assert_equal "ACCESS_KEY_ID", mapping.fetch("D8N_R2_DATE9JA_PRODUCTION_ACCESS_KEY_ID")
    assert_equal "SECRET_ACCESS_KEY", mapping.fetch("D8N_R2_DATE9JA_PRODUCTION_SECRET_ACCESS_KEY")
    assert_equal "STAGING_R2_BUCKET", mapping.fetch("D8N_R2_DATE9JA_PRODUCTION_BUCKET")
    refute_equal mapping.fetch("D8N_R2_DATEZA_PRODUCTION_ACCESS_KEY_ID"), mapping.fetch("D8N_R2_DATE9JA_PRODUCTION_ACCESS_KEY_ID")
  end
end
