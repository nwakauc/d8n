module Api
  module V1
    module Admin
      # Base for all admin/moderation endpoints. Authorization is server-derived
      # from the ordinary brand-scoped session: the caller must be authenticated
      # (else 401) AND resolve to an active AdminUser with an active assignment for
      # the request's brand (else 403). Ordinary authenticated users get 403.
      class BaseController < ApplicationController
        before_action :authenticate_admin!

        private

        def authenticate_admin!
          return render_admin_unauthorized if Current.user.blank?

          admin_user = ::Admin::ModeratorContext.resolve(user: Current.user, brand: Current.brand)
          return render_admin_forbidden if admin_user.blank?

          Current.admin_user = admin_user
        end

        def render_admin_unauthorized
          render json: { error: "unauthorized" }, status: :unauthorized
        end

        def render_admin_forbidden
          render json: { error: "forbidden" }, status: :forbidden
        end
      end
    end
  end
end
