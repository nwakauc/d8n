require "test_helper"
require "json"
require "open3"
require "yaml"

class SolidQueueConfigurationTest < ActiveSupport::TestCase
  EXPECTED_TABLES = %w[
    solid_queue_blocked_executions
    solid_queue_claimed_executions
    solid_queue_failed_executions
    solid_queue_jobs
    solid_queue_pauses
    solid_queue_processes
    solid_queue_ready_executions
    solid_queue_recurring_executions
    solid_queue_recurring_tasks
    solid_queue_scheduled_executions
    solid_queue_semaphores
  ].freeze

  test "production uses Solid Queue with only primary and queue databases" do
    config = production_config

    assert_equal "solid_queue", config.fetch("adapter")
    assert_equal({ "database" => { "writing" => "queue" } }, config.fetch("connects_to"))
    assert_equal %w[ primary queue ], config.fetch("databases")
    assert_equal "null_store", config.fetch("cache_store")
    assert_equal "postgresql", config.fetch("cable_adapter")
  end

  test "the official Solid Queue schema and worker executable are installed" do
    schema = Rails.root.join("db/queue_schema.rb").read
    tables = schema.scan(/create_table "([^"]+)"/).flatten

    assert_equal EXPECTED_TABLES.sort, tables.sort
    assert_predicate Rails.root.join("bin/jobs"), :executable?
    assert Rails.root.join("config/queue.yml").file?
    assert Rails.root.join("config/recurring.yml").file?
  end

  test "Solid Cache and Solid Cable are not application dependencies" do
    dependencies = Bundler.locked_gems.dependencies.keys

    assert_includes dependencies, "solid_queue"
    assert_not_includes dependencies, "solid_cache"
    assert_not_includes dependencies, "solid_cable"
  end

  test "Puma never starts the Solid Queue supervisor" do
    puma_config = Rails.root.join("config/puma.rb").read

    assert_not_includes puma_config, "SOLID_QUEUE_IN_PUMA"
    assert_no_match(/plugin\s+:solid_queue/, puma_config)
  end

  test "staging defines a separate Solid Queue worker role" do
    staging = YAML.safe_load_file(Rails.root.join("config/deploy.staging.yml"))
    job_role = staging.dig("servers", "job")

    assert_equal "bin/jobs", job_role.fetch("cmd")
    assert_equal 30, job_role.fetch("stop_timeout")
    assert_equal [ "145.241.185.41" ], job_role.fetch("hosts")
    assert_not staging.dig("env", "clear").key?("SOLID_QUEUE_IN_PUMA")
  end

  private

  def production_config
    script = <<~'RUBY'
      require "json"

      payload = {
        adapter: ActiveJob::Base.queue_adapter_name,
        connects_to: Rails.application.config.solid_queue.connects_to,
        databases: ActiveRecord::Base.configurations.configs_for(env_name: "production").map(&:name).sort,
        cache_store: Rails.application.config.cache_store,
        cable_adapter: ActionCable.server.config.cable[:adapter]
      }
      puts "SOLID_QUEUE_CONFIG=#{JSON.generate(payload)}"
    RUBY

    env = {
      "RAILS_ENV" => "production",
      "SECRET_KEY_BASE_DUMMY" => "1",
      "D8N_DATABASE_PASSWORD" => "configuration-test-only"
    }
    command = [ RbConfig.ruby, Rails.root.join("bin/rails").to_s, "runner", script ]
    stdout, stderr, status = Open3.capture3(env, *command)

    assert status.success?, <<~MESSAGE
      Production Solid Queue configuration check failed.
      stdout: #{stdout}
      stderr: #{stderr}
    MESSAGE

    line = stdout.lines.find { |output| output.start_with?("SOLID_QUEUE_CONFIG=") }
    assert line, "Production runner did not emit Solid Queue configuration"

    JSON.parse(line.delete_prefix("SOLID_QUEUE_CONFIG="))
  end
end
