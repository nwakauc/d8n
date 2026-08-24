class Api::V1::Auth::SessionsController < ApplicationController
  before_action :authenticate_user!

  def destroy
    Identity::SessionRevoker.call(
      session: Current.session,
      ip_address: request.remote_ip,
      user_agent: request.user_agent
    )
    clear_browser_session_cookie

    head :no_content
  end
end
