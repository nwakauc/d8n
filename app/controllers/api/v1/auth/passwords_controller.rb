class Api::V1::Auth::PasswordsController < ApplicationController
  skip_before_action :verify_browser_session_csrf!, only: %i[register login reactivate]
  before_action :authorize_session_mode!, only: %i[register login reactivate]

  before_action :authenticate_user!, only: :update

  def register
    if Current.user.present?
      render json: { error: "already_authenticated" }, status: :conflict
      return
    end

    result = Identity::PasswordRegistration.call(
      brand: Current.brand,
      **password_params,
      ip_address: request.remote_ip,
      user_agent: request.user_agent
    )

    render_result(result, failure_error: "registration_unavailable")
  end

  def login
    result = Identity::PasswordLogin.call(
      brand: Current.brand,
      **password_params,
      ip_address: request.remote_ip,
      user_agent: request.user_agent
    )

    render_result(result, failure_error: "invalid_credentials")
  end

  # Explicit reactivation of a deactivated account — see Identity::AccountReactivation.
  # Reuses the login request/response contract exactly (identifier + password in,
  # session payload out) since re-proving the password is the reactivation
  # confirmation itself.
  def reactivate
    if Current.user.present?
      render json: { error: "already_authenticated" }, status: :conflict
      return
    end

    result = Identity::AccountReactivation.call(
      brand: Current.brand,
      **password_params,
      ip_address: request.remote_ip,
      user_agent: request.user_agent
    )

    if !result.success? && result.error == :account_not_deactivated
      render json: { error: "account_not_deactivated" }, status: :conflict
      return
    end

    render_result(result, failure_error: "invalid_credentials")
  end

  def update
    result = Identity::PasswordChange.call(
      session: Current.session,
      **password_change_params,
      ip_address: request.remote_ip,
      user_agent: request.user_agent
    )

    if result.success?
      render json: { message: "Password updated." }
      return
    end

    case result.error
    when :invalid_current_password
      render json: { error: "invalid_current_password" }, status: :unauthorized
    when :rate_limited
      response.set_header("Retry-After", result.retry_after.to_s)
      render json: { error: "rate_limited" }, status: :too_many_requests
    when :password_credential_required
      render json: { error: "password_credential_required" }, status: :conflict
    else
      render json: { error: result.error.to_s }, status: :unprocessable_entity
    end
  end

  private

  def password_params
    params.permit(:identifier, :password, :device_name).to_h.symbolize_keys
  end

  def password_change_params
    params.permit(:current_password, :password, :password_confirmation).to_h.symbolize_keys
  end

  def render_result(result, failure_error:)
    if result.success?
      render json: session_payload(result), status: :created
      return
    end

    case result.error
    when :brand_required, :auth_method_unavailable
      render json: { error: result.error.to_s }, status: :not_found
    when :rate_limited
      response.set_header("Retry-After", result.retry_after.to_s)
      render json: { error: "rate_limited" }, status: :too_many_requests
    when :invalid_credentials
      render json: { error: failure_error }, status: :unauthorized
    when :account_deactivated
      render json: { error: "account_deactivated" }, status: :conflict
    else
      render json: { error: failure_error }, status: :unprocessable_entity
    end
  end

  def session_payload(result)
    verification = Identity::VerificationState.call(session: result.session, brand: Current.brand)
    verified = verification.verified

    payload = {
      expires_at: result.session.expires_at.iso8601,
      user_id: result.user.id,
      brand: {
        slug: Current.brand.slug,
        name: Current.brand.name
      },
      identifier: {
        kind: verification.kind,
        verified:,
        masked_destination: verification.masked_destination
      },
      # Explicit, stable signal so the client can route into the verification-code
      # step and know which channel a code was sent to. On registration a code is
      # dispatched asynchronously; on login of a still-unverified identifier this
      # tells the client verification is outstanding (use the resend endpoint) — no
      # code is re-sent by login itself.
      verification_required: !verified,
      verification_channel: verified ? nil : verification.kind,
      verification: {
        code_dispatched: verification.code_dispatched,
        resend_available_in: verification.resend_available_in
      },
      onboarding: Profiles::OnboardingStatus.call(user: result.user, brand: Current.brand)
    }
    if browser_session_mode?
      payload[:browser_session] = persist_browser_session(raw_token: result.raw_token, session: result.session)
    else
      payload[:token] = result.raw_token
      payload[:token_type] = "Bearer"
    end
    payload
  end

  def authorize_session_mode!
    mode = params[:session_mode].to_s
    return if mode.blank?
    return render(json: { error: "invalid_session_mode" }, status: :unprocessable_entity) unless browser_session_mode?
    return render(json: { error: "browser_session_not_configured" }, status: :not_found) unless
      Identity::BrowserSession.enabled?(brand: Current.brand)
    return if Identity::BrowserSession.origin_allowed?(request:)

    render json: { error: "browser_session_origin_not_allowed" }, status: :forbidden
  end

  def browser_session_mode?
    params[:session_mode].to_s == "browser"
  end
end
