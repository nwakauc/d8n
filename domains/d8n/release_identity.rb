module D8n
  module ReleaseIdentity
    BOOTED_AT = Time.now.utc.freeze
    SHA_PATTERN = /\A[0-9a-f]{40}\z/i

    module_function

    def call
      git_sha = ENV["D8N_GIT_SHA"].to_s.strip.presence
      git_sha = nil unless git_sha&.match?(SHA_PATTERN)
      image_version = ENV["KAMAL_VERSION"].to_s.strip.presence

      {
        app: "d8n",
        git_sha:,
        release: image_version || git_sha,
        image_version:,
        environment: ENV["D8N_DEPLOYMENT_ENV"].presence || Rails.env,
        rails_environment: Rails.env,
        build_timestamp: iso8601_or_nil(ENV["D8N_BUILD_TIMESTAMP"]),
        booted_at: BOOTED_AT.iso8601
      }
    end

    def iso8601_or_nil(value)
      return if value.blank?

      Time.iso8601(value).utc.iso8601
    rescue ArgumentError
      nil
    end
    private_class_method :iso8601_or_nil
  end
end
