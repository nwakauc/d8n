module Api
  module V1
    module Hq
      class OperatorsController < BaseController
        requires_admin_capability ::Admin::Capabilities::OPERATORS_READ, only: :index
        requires_admin_capability ::Admin::Capabilities::OPERATORS_MANAGE, only: %i[create update]

        rescue_from ::Admin::OperatorError, with: :render_operator_error

        def index
          assignments = AdminAssignment.kept.includes(:admin_role, admin_user: :admin_mfa_credentials)
            .where(brand: Current.brand).order(:admin_user_id).limit(100)
          render json: {
            operators: assignments.map { |assignment| ::Admin::OperatorSerializer.call(assignment:) }
          }
        end

        def create
          assignment = ::Admin::OperatorManagement.assign(
            actor_context: Current.admin_context,
            brand: Current.brand,
            email: params[:email],
            role_name: params[:role],
            session: Current.session
          )
          render json: { operator: ::Admin::OperatorSerializer.call(assignment:) }, status: :created
        end

        def update
          assignment = ::Admin::OperatorManagement.update(
            actor_context: Current.admin_context,
            brand: Current.brand,
            admin_user_id: params[:id],
            role_name: params[:role],
            status: params[:status],
            session: Current.session
          )
          render json: { operator: ::Admin::OperatorSerializer.call(assignment:) }
        end

        private

        def render_operator_error(error)
          status = error.code == "operator_unavailable" ? :not_found : :unprocessable_entity
          render json: { error: error.code }, status:
        end
      end
    end
  end
end
