class Api::V1::SessionsController < ApplicationController
  before_action :authenticate_user!

  # The member's own real, active sessions for this brand — newest-active
  # first. Distinct from Api::V1::Auth::SessionsController#destroy (revokes
  # ONLY the caller's current session as part of logout); this is a
  # self-service device list with per-device revoke.
  def index
    sessions = Current.user.sessions.active.where(brand: Current.brand).order(last_used_at: :desc)

    render json: { sessions: sessions.map { |session| session_payload(session) } }
  end

  def destroy
    session = Current.user.sessions.where(brand: Current.brand).find(params[:id])
    return render json: { error: "current_session" }, status: :conflict if session.id == Current.session.id

    Identity::SessionRevoker.call(session:, ip_address: request.remote_ip, user_agent: request.user_agent)

    head :no_content
  rescue ActiveRecord::RecordNotFound
    render json: { error: "session_unavailable" }, status: :not_found
  end

  private

  def session_payload(session)
    {
      id: session.id,
      device_name: session.device_name,
      user_agent: session.user_agent,
      ip_address: session.ip_address,
      last_used_at: session.last_used_at.iso8601,
      created_at: session.created_at.iso8601,
      current: session.id == Current.session.id
    }
  end
end
