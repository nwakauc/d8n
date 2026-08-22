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

if allowed_origins.any?
  Rails.application.config.middleware.insert_before 0, Rack::Cors do
    allow do
      origins(*allowed_origins)

      resource "/api/v1/*",
        headers: %w[ Accept Authorization Content-Type ],
        expose: %w[ Retry-After ],
        methods: %i[ get post put patch delete options head ],
        max_age: 600
    end
  end
end
