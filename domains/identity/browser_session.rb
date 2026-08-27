module Identity
  class BrowserSession
    COOKIE_NAME = "d8n_web_session"
    COOKIE_PATH = "/api/v1"
    CSRF_HEADER = "X-CSRF-Token"
    SAFE_METHODS = %w[GET HEAD OPTIONS].freeze

    class << self
      def enabled?(brand:)
        D8n::Platform::BrandRegistry.fetch(brand:).capability_enabled?("id.session.browser_persistence")
      rescue D8n::Platform::BrandRegistry::UnsupportedBrand
        false
      end

      def csrf_token(session:)
        HmacDigest.call(
          purpose: "browser-session-csrf",
          value: "#{session.id}:#{session.token_digest}"
        )
      end

      def valid_csrf_token?(session:, token:)
        supplied = token.to_s
        expected = csrf_token(session:)
        supplied.bytesize == expected.bytesize && ActiveSupport::SecurityUtils.secure_compare(supplied, expected)
      end

      def csrf_required?(request:, authentication_source:)
        authentication_source == :cookie && !SAFE_METHODS.include?(request.request_method)
      end

      def origin_allowed?(request:)
        origin = request.headers["Origin"].to_s.strip
        return request.headers["Sec-Fetch-Site"].to_s != "cross-site" if origin.blank?

        origin == request.base_url || configured_origins.include?(origin)
      end

      def cookie_options(expires_at: nil)
        options = {
          httponly: true,
          secure: secure?,
          same_site: same_site,
          path: COOKIE_PATH
        }
        if expires_at
          options[:expires] = expires_at
          options[:max_age] = [ expires_at - Time.current, 0 ].max.to_i
        end
        options
      end

      def secure?
        Rails.env.production?
      end

      # D8N's browser session cookie is always host-only (no `Domain=` is ever
      # set — see #cookie_options) and every web frontend is required to sit
      # behind a same-origin reverse proxy (e.g. Vercel `/api/*` rewrites to
      # the shared D8N backend — the browser must never call the D8N hostname
      # directly). Under that architecture the cookie is always genuinely
      # first-party, so `:lax` is correct and strictly safer than `:none`:
      # `:none` was a workaround for the old cross-site topology, which is no
      # longer a supported browser flow for any D8N brand.
      def same_site
        :lax
      end

      private

      def configured_origins
        Array(Rails.application.config.x.cors_origins)
      end
    end
  end
end
