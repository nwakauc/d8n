module Api
  module V1
    module Admin
      # Base for existing moderation endpoints. Authorization is the same
      # capability + MFA boundary used by HQ; domain writes retain their own
      # transactional audit behavior.
      class BaseController < ApplicationController
        before_action :authenticate_admin!
        before_action :require_admin_mfa!
        before_action :disable_admin_http_caching

        def self.requires_admin_capability(capability, **options)
          before_action(**options) { authorize_admin_capability!(capability) }
        end

        private

        def authenticate_admin!
          return render_admin_unauthorized if Current.user.blank?

          context = ::Admin::AuthorizationContext.resolve(user: Current.user, brand: Current.brand)
          return render_admin_forbidden if context.blank?

          Current.admin_context = context
          Current.admin_user = context.admin_user
          Current.permissions = context.capabilities
        end

        def require_admin_mfa!
          return if Current.session&.admin_mfa_verified_for?(Current.admin_user)

          render json: { error: "admin_mfa_required" }, status: :forbidden
        end

        def authorize_admin_capability!(capability)
          return if Current.admin_context&.allowed?(capability)

          render_admin_forbidden
        end

        def render_admin_unauthorized
          render json: { error: "unauthorized" }, status: :unauthorized
        end

        def render_admin_forbidden
          render json: { error: "forbidden" }, status: :forbidden
        end

        def disable_admin_http_caching
          response.headers["Cache-Control"] = "no-store, private"
          response.headers.delete("ETag")
        end
      end
    end
  end
end
