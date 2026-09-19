module Api
  module V1
    module Hq
      class AuthController < ApplicationController
        skip_before_action :verify_browser_session_csrf!, only: :login

        def login
          result = Identity::PasswordLogin.call(
            brand: Current.brand,
            **password_params,
            ip_address: request.remote_ip,
            user_agent: request.user_agent,
            # Query the concrete FK explicitly. `find_by(user:)` makes
            # ActiveRecord emit a predicate against a singular `"user"` table
            # without a join, which PostgreSQL rejects during HQ login.
            session_issuer: ->(user:) { AdminUser.kept.active.find_by(user_id: user.id) }
          )
          return render(json: { error: "invalid_credentials" }, status: :unauthorized) unless result.success?

          context = ::Admin::AuthorizationContext.resolve(user: result.user, brand: Current.brand)
          unless context
            result.session.update!(revoked_at: Time.current, revocation_reason: "no_hq_assignment")
            return render(json: { error: "forbidden" }, status: :forbidden)
          end

          cookies[Identity::HqBrowserSession::COOKIE_NAME] = Identity::HqBrowserSession.cookie_options(
            expires_at: result.session.expires_at
          ).merge(value: result.raw_token)
          render json: payload(result), status: :created
        end

        def show
          return unless authenticate_hq_operator!
          render json: {
            session: {
              expires_at: Current.session.expires_at.iso8601,
              csrf_token: Identity::HqBrowserSession.csrf_token(session: Current.session)
            },
            operator: { user_id: Current.user.id, admin_user_id: Current.admin_user.id }
          }
        end

        def destroy
          return unless authenticate_hq_operator!
          Current.session.update!(revoked_at: Time.current, revocation_reason: "logout")
          cookies.delete(Identity::HqBrowserSession::COOKIE_NAME, **Identity::HqBrowserSession.cookie_options)
          head :no_content
        end

        private

        def password_params
          params.permit(:identifier, :password, :device_name).to_h.symbolize_keys
        end

        def payload(result)
          { session: { expires_at: result.session.expires_at.iso8601, csrf_token: Identity::HqBrowserSession.csrf_token(session: result.session) },
            operator: { user_id: result.user.id, admin_user_id: result.session.admin_user_id, brand: Current.brand.slug } }
        end

        def authenticate_hq_operator!
          token = cookies[Identity::HqBrowserSession::COOKIE_NAME]
          result = Identity::HqOperatorSessionAuthenticator.call(token:)
          unless result.success?
            render json: { error: result.error == :expired_session ? "session_expired" : "unauthorized" }, status: :unauthorized
            return false
          end
          Current.authentication_source = :hq_cookie
          Current.session = result.session
          Current.user = result.user
          context = ::Admin::AuthorizationContext.resolve(user: Current.user, brand: Current.brand)
          unless context
            render json: { error: "forbidden" }, status: :forbidden
            return false
          end
          Current.admin_context = context
          Current.admin_user = context.admin_user
          true
        end
      end
    end
  end
end
