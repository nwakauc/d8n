require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Staging also boots with RAILS_ENV=production, so Rails.env cannot distinguish
  # storage environments. D8N_DEPLOYMENT_ENV makes that boundary explicit and
  # each configured brand receives its own private Active Storage service.
  r2_storage_enabled = ENV["D8N_R2_ENABLED"] == "true"
  media_storage_environment = nil
  r2_brand_slugs = []
  if r2_storage_enabled
    media_storage_environment = ENV["D8N_DEPLOYMENT_ENV"].to_s
    unless %w[ staging production ].include?(media_storage_environment)
      raise "Private media storage requires D8N_DEPLOYMENT_ENV=staging or production"
    end

    r2_brand_slugs = ENV["D8N_R2_BRANDS"].to_s.split(",").map(&:strip).reject(&:blank?).uniq
    raise "Private media storage requires at least one D8N_R2_BRANDS entry" if r2_brand_slugs.empty?

    invalid_r2_brand_slugs = r2_brand_slugs.reject { |slug| slug.match?(/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/) }
    if invalid_r2_brand_slugs.any?
      raise "Private media storage has invalid D8N_R2_BRANDS entries: #{invalid_r2_brand_slugs.join(', ')}"
    end

    required_r2_environment = [ "D8N_R2_ENDPOINT" ] + r2_brand_slugs.flat_map do |slug|
      prefix = "D8N_R2_#{slug.tr('-', '_').upcase}_#{media_storage_environment.upcase}"
      [ "#{prefix}_ACCESS_KEY_ID", "#{prefix}_SECRET_ACCESS_KEY", "#{prefix}_BUCKET" ]
    end
    missing_r2_environment = required_r2_environment.select { |name| ENV[name].blank? }
    if missing_r2_environment.any?
      raise "Private media storage requires R2 configuration: #{missing_r2_environment.join(', ')}"
    end
  end

  default_r2_service = if r2_storage_enabled
    "r2_#{r2_brand_slugs.first}_#{media_storage_environment}".to_sym
  end
  config.active_storage.service = default_r2_service || :local
  config.active_storage.variant_processor = :disabled
  # The direct-to-R2 profile-photo API (owner-scoped upload intent, verified
  # attachment, and short-lived signed retrieval) is enabled exactly when private
  # R2 storage is selected. Without R2 the only storage is local disk, whose
  # direct-upload/delivery depends on the generic Active Storage routes disabled
  # below, so the API stays closed and fail-safe. Public/other-user delivery,
  # safe re-encoding, EXIF removal, and moderation remain gated (ADR 0011).
  config.x.profile_photos_enabled = r2_storage_enabled
  config.x.r2_storage_enabled = r2_storage_enabled
  config.x.media_storage_environment = media_storage_environment
  config.x.r2_brand_slugs = r2_brand_slugs
  # Never expose Active Storage's generic upload/delivery routes: object identity
  # and delivery are mediated only by the D8N-controlled profile-photo API.
  config.active_storage.draw_routes = false

  # Assume all access to the app is happening through a SSL-terminating reverse proxy.
  config.assume_ssl = true

  # Client IP for abuse protection. The deployment topology is
  # Cloudflare -> kamal-proxy -> Puma; the immediate peer is a local/private proxy
  # that APPENDS the real client IP to X-Forwarded-For. Rails' default
  # ActionDispatch::RemoteIp trusts only loopback/private ranges as proxies, so it
  # returns the rightmost untrusted (real) address and a client-supplied
  # X-Forwarded-For cannot spoof it. For non-standard topologies, additional proxy
  # CIDRs may be trusted via D8N_TRUSTED_PROXIES (comma-separated).
  extra_trusted_proxies = ENV["D8N_TRUSTED_PROXIES"].to_s.split(",").map(&:strip).reject(&:blank?)
  if extra_trusted_proxies.any?
    require "ipaddr"
    config.action_dispatch.trusted_proxies =
      ActionDispatch::RemoteIp::TRUSTED_PROXIES + extra_trusted_proxies.map { |proxy| IPAddr.new(proxy) }
  end

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  config.force_ssl = true

  # Skip http-to-https redirect for the default health check endpoint.
  # config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Change to "debug" to log everything (including potentially personally-identifiable information!)
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # D8N has no production cache dependency yet. Add one only with a measured use.
  config.cache_store = :null_store

  # Replace the default in-process and non-durable queuing backend for Active Job.
  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue } }

  # Ignore bad email addresses and do not raise email delivery errors.
  # Set this to true and configure the email server for immediate delivery to raise delivery errors.
  # config.action_mailer.raise_delivery_errors = false

  # Set host to be used by links generated in mailer templates.
  config.action_mailer.default_url_options = { host: "example.com" }

  # Specify outgoing SMTP server. Remember to add smtp/* credentials via rails credentials:edit.
  # config.action_mailer.smtp_settings = {
  #   user_name: Rails.application.credentials.dig(:smtp, :user_name),
  #   password: Rails.application.credentials.dig(:smtp, :password),
  #   address: "smtp.example.com",
  #   port: 587,
  #   authentication: :plain
  # }

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # Enable DNS rebinding protection and other `Host` header attacks.
  # config.hosts = [
  #   "example.com",     # Allow requests from example.com
  #   /.*\.example\.com/ # Allow requests from subdomains like `www.example.com`
  # ]
  #
  # Skip DNS rebinding protection for the default health check endpoint.
  # config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
end
