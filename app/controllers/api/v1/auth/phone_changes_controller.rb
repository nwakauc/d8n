class Api::V1::Auth::PhoneChangesController < ApplicationController
  before_action :authenticate_user!

  def create
    result = Identity::PhoneChangeRequester.call(session: Current.session, phone: params[:phone], current_password: params[:current_password], ip_address: request.remote_ip, user_agent: request.user_agent)
    return render json: { message: "A verification code has been sent to the new phone number." }, status: :accepted if result.success?

    response.set_header("Retry-After", result.retry_after.to_s) if result.retry_after.to_i.positive?
    render_error(result.error)
  end

  def update
    result = Identity::PhoneChangeVerifier.call(session: Current.session, phone: params[:phone], code: params[:code], ip_address: request.remote_ip, user_agent: request.user_agent)
    return render json: { identifier: { kind: "phone", verified: true }, revoked_session_count: result.revoked_session_count } if result.success?

    render_error(result.error)
  end

  private

  def render_error(error)
    status = case error
    when :verification_code_expired then :gone
    when :verification_code_used then :conflict
    when :verification_attempts_exhausted then :too_many_requests
    when :invalid_current_password then :unauthorized
    when :delivery_unavailable then :service_unavailable
    else :unprocessable_entity
    end
    render json: { error: error.to_s }, status:
  end
end
