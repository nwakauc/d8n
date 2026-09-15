require "uri"

module D8n
  # Fail-fast validation for the Date9ja production tenant. It validates names
  # and topology without ever including secret values in an exception.
  class Date9jaProductionConfiguration
    class ConfigurationError < StandardError; end

    REQUIRED = %w[
      DATE9JA_API_HOST
      D8N_ALLOWED_HOSTS
      D8N_CORS_ORIGINS
      D8N_DATE9JA_APP_URL
      D8N_DATE9JA_EMAIL_FROM
      D8N_DEFAULT_MAILER_HOST
      D8N_R2_ENDPOINT
      D8N_R2_DATE9JA_PRODUCTION_ACCESS_KEY_ID
      D8N_R2_DATE9JA_PRODUCTION_SECRET_ACCESS_KEY
      D8N_R2_DATE9JA_PRODUCTION_BUCKET
      RESEND_API_KEY
      D8N_AR_ENCRYPTION_PRIMARY_KEY
      D8N_AR_ENCRYPTION_DETERMINISTIC_KEY
      D8N_AR_ENCRYPTION_KEY_DERIVATION_SALT
      D8N_DATABASE_HOST
      D8N_DATABASE_PORT
      D8N_DATABASE_NAME
      D8N_DATABASE_USERNAME
      D8N_DATABASE_PASSWORD
      D8N_QUEUE_DATABASE_NAME
    ].freeze
    STORAGE_SERVICE = :r2_date9ja_production

    def self.validate!(environment: ENV, storage_service_checker: nil)
      new(environment:, storage_service_checker:).validate!
    end

    def initialize(environment:, storage_service_checker: nil)
      @environment = environment
      @storage_service_checker = storage_service_checker || ->(_name) { true }
    end

    def validate!
      errors = REQUIRED.filter_map do |name|
        "#{name} is missing" if environment[name].to_s.strip.empty?
      end
      validate_topology(errors)
      validate_storage_service(errors)

      return true if errors.empty?

      raise ConfigurationError, "Invalid Date9ja production configuration: #{errors.join('; ')}"
    end

    private

    attr_reader :environment, :storage_service_checker

    def validate_topology(errors)
      api_host = environment["DATE9JA_API_HOST"].to_s.strip.downcase
      allowed_hosts = csv("D8N_ALLOWED_HOSTS").map(&:downcase)
      cors_origins = csv("D8N_CORS_ORIGINS")
      app_url = environment["D8N_DATE9JA_APP_URL"].to_s.strip

      errors << "DATE9JA_API_HOST must be a hostname without scheme, port, or path" unless valid_hostname?(api_host)
      errors << "D8N_ALLOWED_HOSTS must include DATE9JA_API_HOST" unless allowed_hosts.include?(api_host)
      errors << "D8N_ALLOWED_HOSTS must contain only exact hostnames" unless allowed_hosts.all? { |host| valid_hostname?(host) }
      errors << "D8N_CORS_ORIGINS must not contain wildcards" if cors_origins.any? { |origin| origin.include?("*") }
      errors << "D8N_DATE9JA_APP_URL must be an HTTPS origin" unless https_origin?(app_url)
      errors << "D8N_CORS_ORIGINS must include D8N_DATE9JA_APP_URL" unless cors_origins.include?(app_url)
      errors << "D8N_EMAIL_PROVIDER must be resend" unless environment["D8N_EMAIL_PROVIDER"] == "resend"
      errors << "D8N_R2_ENABLED must be true" unless environment["D8N_R2_ENABLED"] == "true"
      errors << "D8N_DEPLOYMENT_ENV must be production" unless environment["D8N_DEPLOYMENT_ENV"] == "production"
      errors << "D8N_R2_BRANDS must include date9ja" unless csv("D8N_R2_BRANDS").include?("date9ja")
      errors << "D8N_R2_ENDPOINT must be an HTTPS URL" unless https_url?(environment["D8N_R2_ENDPOINT"])
      errors << "D8N_DATE9JA_EMAIL_FROM must be a non-placeholder email sender" unless valid_sender?
      errors << "D8N_DATABASE_PORT must be numeric" unless environment["D8N_DATABASE_PORT"].to_s.match?(/\A\d+\z/)
      if environment["D8N_DATABASE_NAME"].to_s == environment["D8N_QUEUE_DATABASE_NAME"].to_s
        errors << "D8N_QUEUE_DATABASE_NAME must be separate from D8N_DATABASE_NAME"
      end
    end

    def validate_storage_service(errors)
      storage_service_checker.call(STORAGE_SERVICE)
    rescue StandardError
      errors << "Active Storage service r2_date9ja_production is not configured"
    end

    def csv(name)
      environment[name].to_s.split(",").map(&:strip).reject(&:empty?).uniq
    end

    def valid_hostname?(value)
      value.match?(/\A(?=.{1,253}\z)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}\z/)
    end

    def https_origin?(value)
      uri = URI.parse(value)
      uri.scheme == "https" && uri.host.present? && uri.port == 443 && uri.path.to_s.empty? &&
        uri.query.nil? && uri.fragment.nil?
    rescue URI::InvalidURIError
      false
    end

    def https_url?(value)
      uri = URI.parse(value.to_s)
      uri.scheme == "https" && uri.host.present?
    rescue URI::InvalidURIError
      false
    end

    def valid_sender?
      sender = environment["D8N_DATE9JA_EMAIL_FROM"].to_s
      sender.match?(/@[^>\s]+\.[^>\s]+>?\z/) && !sender.match?(/@(example\.com|[^>\s]+\.example)>?\z/i)
    end
  end
end
