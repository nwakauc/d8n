class Api::V1::Auth::PasswordsController < ApplicationController
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

  private

  def password_params
    params.permit(:identifier, :password, :device_name).to_h.symbolize_keys
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
    else
      render json: { error: failure_error }, status: :unprocessable_entity
    end
  end

  def session_payload(result)
    identifier = result.credential.identity_identifier

    {
      token: result.raw_token,
      token_type: "Bearer",
      expires_at: result.session.expires_at.iso8601,
      user_id: result.user.id,
      brand: {
        slug: Current.brand.slug,
        name: Current.brand.name
      },
      identifier: {
        kind: identifier.kind,
        verified: identifier.verified_at.present?
      }
    }
  end
end
