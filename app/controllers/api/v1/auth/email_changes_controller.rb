class Api::V1::Auth::EmailChangesController < ApplicationController
  before_action :authenticate_user!

  def create
    result = Identity::EmailChangeRequester.call(
      session: Current.session,
      email: email_change_params[:email],
      current_password: email_change_params[:current_password],
      ip_address: request.remote_ip,
      user_agent: request.user_agent
    )

    if result.success?
      render json: { message: "A verification code has been sent to the new email address." }, status: :accepted
      return
    end

    render_request_error(result)
  end

  def update
    result = Identity::EmailChangeVerifier.call(
      session: Current.session,
      email: email_change_params[:email],
      code: email_change_params[:code],
      ip_address: request.remote_ip,
      user_agent: request.user_agent
    )

    if result.success?
      render json: {
        identifier: { kind: "email", verified: true },
        revoked_session_count: result.revoked_session_count
      }
      return
    end

    status = case result.error
    when :email_change_unavailable then :unprocessable_entity
    when :verification_code_expired then :gone
    when :verification_code_used then :conflict
    when :verification_attempts_exhausted then :too_many_requests
    else :unauthorized
    end
    render json: { error: result.error.to_s }, status:
  end

  private

  def email_change_params
    params.permit(:email, :current_password, :code)
  end

  def render_request_error(result)
    case result.error
    when :invalid_current_password
      render json: { error: "invalid_current_password" }, status: :unauthorized
    when :password_credential_required
      render json: { error: "password_credential_required" }, status: :conflict
    when :rate_limited, :verification_resend_too_soon, :verification_rate_limited
      response.set_header("Retry-After", result.retry_after.to_s)
      render json: { error: result.error.to_s }, status: :too_many_requests
    when :delivery_unavailable
      render json: { error: "delivery_unavailable" }, status: :service_unavailable
    else
      render json: { error: "email_change_unavailable" }, status: :unprocessable_entity
    end
  end
end
