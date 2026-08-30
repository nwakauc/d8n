module Api
  module V1
    module Admin
      class ReportsController < BaseController
        requires_admin_capability ::Admin::Capabilities::REPORTS_READ, only: %i[index show]
        requires_admin_capability ::Admin::Capabilities::REPORTS_MODERATE, only: :update

        CODE_STATUS = {
          report_unavailable: :not_found,
          invalid_filter: :unprocessable_entity,
          invalid_status: :unprocessable_entity,
          invalid_transition: :unprocessable_entity,
          invalid_note: :unprocessable_entity,
          invalid_cursor: :unprocessable_entity,
          invalid_limit: :unprocessable_entity,
          report_conflict: :conflict
        }.freeze

        rescue_from ::Admin::ModerationError, with: :render_moderation_error
        rescue_from ::Admin::ReportCursor::Invalid do
          render json: { error: "invalid_cursor" }, status: :unprocessable_entity
        end

        def index
          result = ::Admin::ReportQueue.call(
            brand: Current.brand,
            status: params[:status],
            cursor: params[:cursor],
            limit: params[:limit]
          )

          render json: {
            reports: result.reports.map { |report| ::Admin::ReportSerializer.call(report:) },
            next_cursor: result.next_cursor
          }
        end

        def show
          report = ::Admin::ReportDetail.call(
            admin_user: Current.admin_user, brand: Current.brand, report_id: params[:id]
          )

          render json: { report: ::Admin::ReportSerializer.call(report:) }
        end

        def update
          report = ::Admin::TransitionReport.call(
            admin_user: Current.admin_user,
            brand: Current.brand,
            report_id: params[:id],
            target_status: params[:status],
            note: params[:note]
          )

          render json: { report: ::Admin::ReportSerializer.call(report:) }
        end

        private

        def render_moderation_error(error)
          render json: { error: error.code }, status: CODE_STATUS.fetch(error.code, :unprocessable_entity)
        end
      end
    end
  end
end
