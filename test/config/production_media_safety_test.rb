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
      abort "R2 routing enabled without R2" if Rails.configuration.x.r2_storage_enabled
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
      "D8N_DEPLOYMENT_ENV" => "staging",
      "D8N_R2_BRANDS" => "hookus,dateza",
      "D8N_R2_ENDPOINT" => nil
    )

    assert_not status.success?
    assert_includes "#{stdout}\n#{stderr}", "Private media storage requires R2 configuration"
  end

  test "complete R2 configuration selects private storage and the photo API without generic routes" do
    script = <<~'RUBY'
      abort "HookUs staging service not selected" unless Rails.configuration.active_storage.service == :r2_hookus_staging
      abort "photo API not enabled with R2" unless Rails.configuration.x.profile_photos_enabled
      abort "R2 routing not enabled" unless Rails.configuration.x.r2_storage_enabled

      active_storage_paths = Rails.application.routes.routes.filter_map do |route|
        path = route.path.spec.to_s
        path if path.start_with?("/rails/active_storage")
      end
      abort "generic Active Storage routes are mounted" if active_storage_paths.any?

      brand = Data.define(:slug)
      hookus = brand.new(slug: "hookus")
      dateza = brand.new(slug: "dateza")
      hookus_name = Media::StorageResolver.service_name(brand: hookus)
      dateza_name = Media::StorageResolver.service_name(brand: dateza)
      abort "HookUs resolved incorrectly" unless hookus_name == "r2_hookus_staging"
      abort "DateZA resolved incorrectly" unless dateza_name == "r2_dateza_staging"

      hookus_service = ActiveStorage::Blob.services.fetch(hookus_name)
      dateza_service = ActiveStorage::Blob.services.fetch(dateza_name)
      abort "HookUs bucket crossed" unless hookus_service.bucket.name == "d8n-staging-media"
      abort "DateZA bucket crossed" unless dateza_service.bucket.name == "d8n-dateza-staging"
      abort "R2 service is public" if hookus_service.public? || dateza_service.public?
      abort "legacy HookUs service rejected" unless Media::StorageResolver.compatible_service?(brand: hookus, service_name: "r2")

      begin
        Media::StorageResolver.service_name(brand: brand.new(slug: "unknown"))
        abort "unknown brand resolved"
      rescue Media::StorageResolver::ConfigurationError
      end
    RUBY
    stdout, stderr, status = production_runner(script, complete_r2_environment("staging"))

    assert status.success?, <<~MESSAGE
      Production R2 configuration check failed.
      stdout: #{stdout}
      stderr: #{stderr}
    MESSAGE
  end

  test "production resolves only production buckets" do
    script = <<~'RUBY'
      brand = Data.define(:slug)
      hookus = ActiveStorage::Blob.services.fetch(Media::StorageResolver.service_name(brand: brand.new(slug: "hookus")))
      dateza = ActiveStorage::Blob.services.fetch(Media::StorageResolver.service_name(brand: brand.new(slug: "dateza")))
      abort "HookUs did not use production" unless hookus.name == :r2_hookus_production
      abort "DateZA did not use production" unless dateza.name == :r2_dateza_production
      abort "HookUs production bucket crossed" unless hookus.bucket.name == "d8n-hookus-prod"
      abort "DateZA production bucket crossed" unless dateza.bucket.name == "d8n-dateza-prod"
    RUBY

    stdout, stderr, status = production_runner(script, complete_r2_environment("production"))

    assert status.success?, <<~MESSAGE
      Production R2 isolation check failed.
      stdout: #{stdout}
      stderr: #{stderr}
    MESSAGE
  end

  private

  def complete_r2_environment(environment)
    bucket_names = if environment == "staging"
      { "HOOKUS" => "d8n-staging-media", "DATEZA" => "d8n-dateza-staging" }
    else
      { "HOOKUS" => "d8n-hookus-prod", "DATEZA" => "d8n-dateza-prod" }
    end

    values = {
      "D8N_R2_ENABLED" => "true",
      "D8N_DEPLOYMENT_ENV" => environment,
      "D8N_R2_BRANDS" => "hookus,dateza",
      "D8N_R2_ENDPOINT" => "https://example.invalid",
      # Legacy HookUs staging blobs retain these names and service_name `r2`.
      "D8N_R2_ACCESS_KEY_ID" => "legacy-access-key",
      "D8N_R2_SECRET_ACCESS_KEY" => "legacy-secret-key",
      "D8N_R2_BUCKET" => "d8n-staging-media"
    }
    bucket_names.each do |brand, bucket|
      prefix = "D8N_R2_#{brand}_#{environment.upcase}"
      values["#{prefix}_ACCESS_KEY_ID"] = "#{brand.downcase}-access-key"
      values["#{prefix}_SECRET_ACCESS_KEY"] = "#{brand.downcase}-secret-key"
      values["#{prefix}_BUCKET"] = bucket
    end
    values
  end

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
