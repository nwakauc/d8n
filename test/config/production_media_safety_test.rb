require "test_helper"
require "open3"

class ProductionMediaSafetyTest < ActiveSupport::TestCase
  test "production boots without generic Active Storage routes or profile photo access" do
    script = <<~'RUBY'
      active_storage_paths = Rails.application.routes.routes.filter_map do |route|
        path = route.path.spec.to_s
        path if path.start_with?("/rails/active_storage")
      end

      abort "generic Active Storage routes are mounted" if active_storage_paths.any?
      abort "development profile photos are enabled" if Rails.configuration.x.profile_photos_enabled
      abort "local storage is not the disabled default" unless Rails.configuration.active_storage.service == :local
    RUBY

    stdout, stderr, status = production_runner(script, "D8N_R2_ENABLED" => "false")

    assert status.success?, <<~MESSAGE
      Production media safety check failed.
      stdout: #{stdout}
      stderr: #{stderr}
    MESSAGE
  end

  test "production refuses to enable R2 with incomplete configuration" do
    stdout, stderr, status = production_runner(
      "abort 'boot unexpectedly succeeded'",
      "D8N_R2_ENABLED" => "true",
      "D8N_R2_ACCESS_KEY_ID" => nil,
      "D8N_R2_SECRET_ACCESS_KEY" => nil,
      "D8N_R2_BUCKET" => nil,
      "D8N_R2_ENDPOINT" => nil
    )

    assert_not status.success?
    assert_includes "#{stdout}\n#{stderr}", "Private media storage requires R2 configuration"
  end

  test "complete R2 configuration selects private storage and the photo API without generic routes" do
    script = <<~'RUBY'
      abort "R2 service not selected" unless Rails.configuration.active_storage.service == :r2
      abort "photo API not enabled with R2" unless Rails.configuration.x.profile_photos_enabled

      active_storage_paths = Rails.application.routes.routes.filter_map do |route|
        path = route.path.spec.to_s
        path if path.start_with?("/rails/active_storage")
      end
      abort "generic Active Storage routes are mounted" if active_storage_paths.any?

      service = ActiveStorage::Blob.service
      abort "S3 service not instantiated" unless service.is_a?(ActiveStorage::Service::S3Service)
      abort "R2 service is public" if service.public?
    RUBY
    stdout, stderr, status = production_runner(
      script,
      "D8N_R2_ENABLED" => "true",
      "D8N_R2_ACCESS_KEY_ID" => "test-access-key",
      "D8N_R2_SECRET_ACCESS_KEY" => "test-secret-key",
      "D8N_R2_BUCKET" => "d8n-test-private",
      "D8N_R2_ENDPOINT" => "https://example.invalid"
    )

    assert status.success?, <<~MESSAGE
      Production R2 configuration check failed.
      stdout: #{stdout}
      stderr: #{stderr}
    MESSAGE
  end

  private

  def production_runner(script, environment = {})
    env = {
      "RAILS_ENV" => "production",
      "SECRET_KEY_BASE_DUMMY" => "1",
      # Active Record Encryption keys are mandatory in production (fail-closed);
      # supply throwaway values so a production boot smoke test can run.
      "D8N_AR_ENCRYPTION_PRIMARY_KEY" => "test-primary-key-000000000000000000000000",
      "D8N_AR_ENCRYPTION_DETERMINISTIC_KEY" => "test-deterministic-key-0000000000000000000",
      "D8N_AR_ENCRYPTION_KEY_DERIVATION_SALT" => "test-key-derivation-salt-00000000000000000"
    }.merge(environment)
    command = [ RbConfig.ruby, Rails.root.join("bin/rails").to_s, "runner", script ]

    Open3.capture3(env, *command)
  end
end
