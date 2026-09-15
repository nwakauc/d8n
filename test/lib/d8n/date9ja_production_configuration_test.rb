require "test_helper"

module D8n
  class Date9jaProductionConfigurationTest < ActiveSupport::TestCase
    test "accepts a complete Date9ja production configuration" do
      assert Date9jaProductionConfiguration.validate!(
        environment: complete_environment,
        storage_service_checker: ->(name) { assert_equal :r2_date9ja_production, name }
      )
    end

    test "reports missing Date9ja R2 variables without exposing configured secrets" do
      environment = complete_environment.merge(
        "D8N_R2_DATE9JA_PRODUCTION_BUCKET" => "",
        "D8N_R2_DATE9JA_PRODUCTION_SECRET_ACCESS_KEY" => "super-secret-value"
      )

      error = assert_raises(Date9jaProductionConfiguration::ConfigurationError) do
        Date9jaProductionConfiguration.validate!(environment:)
      end

      assert_includes error.message, "D8N_R2_DATE9JA_PRODUCTION_BUCKET is missing"
      assert_not_includes error.message, "super-secret-value"
    end

    test "rejects drifted host CORS email database and storage configuration" do
      environment = complete_environment.merge(
        "D8N_ALLOWED_HOSTS" => "api.d8n.tech",
        "D8N_CORS_ORIGINS" => "*",
        "D8N_DATE9JA_EMAIL_FROM" => "Date9ja <from@example.com>",
        "D8N_QUEUE_DATABASE_NAME" => "d8n_production"
      )

      error = assert_raises(Date9jaProductionConfiguration::ConfigurationError) do
        Date9jaProductionConfiguration.validate!(
          environment:,
          storage_service_checker: ->(_name) { raise KeyError }
        )
      end

      assert_includes error.message, "D8N_ALLOWED_HOSTS must include DATE9JA_API_HOST"
      assert_includes error.message, "D8N_CORS_ORIGINS must not contain wildcards"
      assert_includes error.message, "D8N_CORS_ORIGINS must include D8N_DATE9JA_APP_URL"
      assert_includes error.message, "D8N_DATE9JA_EMAIL_FROM must be a non-placeholder email sender"
      assert_includes error.message, "D8N_QUEUE_DATABASE_NAME must be separate"
      assert_includes error.message, "Active Storage service r2_date9ja_production is not configured"
    end

    private

    def complete_environment
      {
        "DATE9JA_API_HOST" => "api.date9ja.love",
        "D8N_ALLOWED_HOSTS" => "api.d8n.tech,dateza-api.d8n.tech,api.date9ja.love",
        "D8N_CORS_ORIGINS" => "https://www.date9ja.love",
        "D8N_DATE9JA_APP_URL" => "https://www.date9ja.love",
        "D8N_DATE9JA_EMAIL_FROM" => "Date9ja <no-reply@date9ja.love>",
        "D8N_DEFAULT_MAILER_HOST" => "api.d8n.tech",
        "D8N_EMAIL_PROVIDER" => "resend",
        "RESEND_API_KEY" => "resend-secret",
        "D8N_R2_ENABLED" => "true",
        "D8N_DEPLOYMENT_ENV" => "production",
        "D8N_R2_BRANDS" => "hookus,dateza,date9ja",
        "D8N_R2_ENDPOINT" => "https://account.r2.cloudflarestorage.com",
        "D8N_R2_DATE9JA_PRODUCTION_ACCESS_KEY_ID" => "r2-access",
        "D8N_R2_DATE9JA_PRODUCTION_SECRET_ACCESS_KEY" => "r2-secret",
        "D8N_R2_DATE9JA_PRODUCTION_BUCKET" => "d8n-date9ja-production",
        "D8N_AR_ENCRYPTION_PRIMARY_KEY" => "primary-secret",
        "D8N_AR_ENCRYPTION_DETERMINISTIC_KEY" => "deterministic-secret",
        "D8N_AR_ENCRYPTION_KEY_DERIVATION_SALT" => "derivation-secret",
        "D8N_DATABASE_HOST" => "database.internal",
        "D8N_DATABASE_PORT" => "5432",
        "D8N_DATABASE_NAME" => "d8n_production",
        "D8N_DATABASE_USERNAME" => "d8n_app",
        "D8N_DATABASE_PASSWORD" => "database-secret",
        "D8N_QUEUE_DATABASE_NAME" => "d8n_production_queue"
      }
    end
  end
end
