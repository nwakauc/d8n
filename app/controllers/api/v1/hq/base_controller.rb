module Api
  module V1
    module Hq
      # Base for all HQ endpoints. Authorization is server-derived from the
      # ordinary brand-scoped session, identically to Api::V1::Admin::BaseController:
      # the caller must be authenticated (else 401) AND resolve to an active
      # AdminUser with an active assignment for the request's brand (else 403).
      # HQ introduces no new authorization mechanism -- see SECURITY-AND-RBAC.md #3.
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
