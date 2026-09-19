module Identity
  class HqBrowserSession
    COOKIE_NAME = "d8n_hq_operator_session"
    CSRF_HEADER = "X-CSRF-Token"
    SAFE_METHODS = %w[GET HEAD OPTIONS].freeze

    class << self
      def csrf_token(session:)
        HmacDigest.call(purpose: "hq-operator-session-csrf", value: "#{session.id}:#{session.token_digest}")
      end

      def valid_csrf_token?(session:, token:)
        supplied = token.to_s
        expected = csrf_token(session:)
        supplied.bytesize == expected.bytesize && ActiveSupport::SecurityUtils.secure_compare(supplied, expected)
      end

      def csrf_required?(request:, authentication_source:)
        authentication_source == :hq_cookie && !SAFE_METHODS.include?(request.request_method)
      end

      def cookie_options(expires_at: nil)
        options = {
          httponly: true,
          secure: Rails.env.production?,
          same_site: Rails.env.production? ? :none : :lax,
          # HQ also consumes the capability-gated /api/v1/admin moderation
          # routes, so the cookie must cover both namespaces. ApplicationController
          # only authenticates this cookie for /api/v1/hq requests and never
          # treats it as a consumer session.
          path: "/api/v1"
        }
        if expires_at
          options[:expires] = expires_at
          options[:max_age] = [ expires_at - Time.current, 0 ].max.to_i
        end
        options
      end
    end
  end
end
