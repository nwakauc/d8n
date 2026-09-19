module Api
  module V1
    module Hq
      class OperatorSessionsController < BaseController
        requires_admin_capability ::Admin::Capabilities::OPERATORS_MANAGE

        def index
          sessions = HqOperatorSession.active.where(admin_user: Current.admin_user).order(last_used_at: :desc)
          render json: { sessions: sessions.map { |session| payload(session) } }
        end

        def destroy
          session = HqOperatorSession.where(admin_user: Current.admin_user).find(params[:id])
          return render json: { error: "current_session" }, status: :conflict if session.id == Current.session.id

          session.update!(revoked_at: Time.current, revocation_reason: "operator_revoked")
          head :no_content
        rescue ActiveRecord::RecordNotFound
          render json: { error: "session_unavailable" }, status: :not_found
        end

        private

        def payload(session)
          { id: session.id, device_name: session.device_name, ip_address: session.ip_address,
            user_agent: session.user_agent, last_used_at: session.last_used_at.iso8601,
            expires_at: session.expires_at.iso8601, current: session.id == Current.session.id }
        end
      end
    end
  end
end
