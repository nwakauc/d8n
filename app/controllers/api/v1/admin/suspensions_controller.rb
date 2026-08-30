module Api
  module V1
    module Admin
      # Brand-level account enforcement: suspend (create) and reinstate (destroy) a
      # profile's participation in the moderator's brand. Explicit domain actions,
      # not arbitrary status mutation. Authorization + brand come from BaseController.
      class SuspensionsController < BaseController
        requires_admin_capability ::Admin::Capabilities::ENFORCEMENTS_MANAGE

        CODE_STATUS = {
          profile_unavailable: :not_found,
          invalid_report: :unprocessable_entity,
          invalid_reason: :unprocessable_entity,
          already_suspended: :conflict,
          not_suspended: :conflict
        }.freeze

        rescue_from ::Admin::ModerationError, with: :render_moderation_error

        def create
          enforcement = ::Admin::SuspendProfile.call(
            admin_user: Current.admin_user,
            brand: Current.brand,
            profile_public_id: params[:profile_id],
            reason: params[:reason],
            report_id: params[:report_id]
          )

          render json: { enforcement: ::Admin::EnforcementSerializer.call(enforcement:) }, status: :created
        end

        def destroy
          enforcement = ::Admin::ReinstateProfile.call(
            admin_user: Current.admin_user,
            brand: Current.brand,
            profile_public_id: params[:profile_id]
          )

          render json: { enforcement: ::Admin::EnforcementSerializer.call(enforcement:) }
        end

        private

        def render_moderation_error(error)
          render json: { error: error.code }, status: CODE_STATUS.fetch(error.code, :unprocessable_entity)
        end
      end
    end
  end
end
