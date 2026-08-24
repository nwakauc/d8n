class Api::V1::Auth::PasswordRecoveriesController < ApplicationController
  # Signed-out password recovery. None of these actions require (or accept) a
  # bearer session; they operate purely on the host-resolved brand.
  NEUTRAL_MESSAGE = "If an eligible account exists, recovery instructions have been sent.".freeze

  # POST /api/v1/auth/password/recovery
  # Always returns the same neutral 202, regardless of whether the identifier
  # exists, is verified, has a password credential, or is throttled. See
  # Identity::RecoveryRequester for the enumeration-resistance rationale.
  def create
    return render(json: { error: "invalid_request" }, status: :unprocessable_entity) if recovery_params[:identifier].blank?

    Identity::RecoveryRequester.call(
      brand: Current.brand,
      identifier: recovery_params[:identifier],
      ip_address: request.remote_ip,
      user_agent: request.user_agent
    )

    render json: { message: NEUTRAL_MESSAGE }, status: :accepted
  end

  # POST /api/v1/auth/password/recovery/verify
  def verify
    result = Identity::RecoveryVerifier.call(
      brand: Current.brand,
      identifier: verify_params[:identifier],
      code: verify_params[:code],
      ip_address: request.remote_ip,
      user_agent: request.user_agent
    )

    if result.success?
      render json: {
        reset_token: result.reset_token,
        expires_at: result.expires_at.iso8601
      }, status: :created
    else
      status = case result.error
      when :verification_code_expired then :gone
      when :verification_code_used then :conflict
      when :verification_attempts_exhausted then :too_many_requests
      else :unauthorized
      end
      render json: { error: result.error.to_s }, status:
    end
  end

  # POST /api/v1/auth/password/recovery/reset
  def reset
    result = Identity::PasswordReset.call(
      brand: Current.brand,
      reset_token: reset_params[:reset_token],
      password: reset_params[:password],
      password_confirmation: reset_params[:password_confirmation],
      ip_address: request.remote_ip,
      user_agent: request.user_agent
    )

    if result.success?
      render json: { message: "Password reset. Sign in with your new password." }
      return
    end

    case result.error
    when :invalid_password
      render json: { error: "invalid_password" }, status: :unprocessable_entity
    else
      render json: { error: "invalid_or_expired_token" }, status: :unauthorized
    end
  end

  private

  def recovery_params
    params.permit(:identifier).to_h.symbolize_keys
  end

  def verify_params
    params.permit(:identifier, :code).to_h.symbolize_keys
  end

  def reset_params
    params.permit(:reset_token, :password, :password_confirmation).to_h.symbolize_keys
  end
end
