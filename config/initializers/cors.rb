default_origins = if Rails.env.development? || Rails.env.test?
  %w[
    http://localhost:3001
    http://127.0.0.1:3001
    http://localhost:5173
    https://dateza.vercel.app
  ]
else
  []
end

allowed_origins = ENV.fetch("D8N_CORS_ORIGINS", default_origins.join(","))
  .split(",")
  .map(&:strip)
  .reject(&:blank?)
  .uniq

if allowed_origins.any? { |origin| origin.include?("*") }
  raise ArgumentError, "D8N_CORS_ORIGINS must contain explicit origins when browser sessions are enabled"
end

Rails.application.config.x.cors_origins = allowed_origins.freeze

if allowed_origins.any?
  Rails.application.config.middleware.insert_before 0, Rack::Cors do
    allow do
      origins(*allowed_origins)

      resource "/api/v1/*",
        headers: %w[ Accept Authorization Content-Type X-CSRF-Token ],
        expose: %w[ Retry-After ],
        methods: %i[ get post put patch delete options head ],
        credentials: true,
        max_age: 600

      # Development/test Disk storage uses Active Storage's direct-upload
      # route. Production disables these generic routes and uploads go straight
      # to R2, so this additional cross-origin surface is local-only.
      if Rails.env.development? || Rails.env.test?
        resource "/rails/active_storage/*",
          headers: %w[ Accept Content-Type Content-MD5 ],
          methods: %i[ put options head ],
          credentials: false,
          max_age: 600
      end
    end
  end
end
