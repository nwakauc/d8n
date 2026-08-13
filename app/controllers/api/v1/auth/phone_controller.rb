class Api::V1::Auth::PhoneController < ApplicationController
  def request_otp
    result = Identity::PhoneOtpRequester.call(
      brand: Current.brand,
      phone: phone_params[:phone],
      ip_address: request.remote_ip,
      user_agent: request.user_agent
    )

    if result.success?
      render json: {
        message: "If the phone number can receive D8N codes, a code has been sent."
      }, status: :accepted
    else
      render_error(result.error, retry_after: result.retry_after)
    end
  end

  def verify_otp
    result = Identity::PhoneOtpVerifier.call(
      brand: Current.brand,
      phone: verify_params[:phone],
      code: verify_params[:code],
      device_name: verify_params[:device_name],
      ip_address: request.remote_ip,
      user_agent: request.user_agent
    )

    if result.success?
      render json: {
        token: result.raw_token,
        token_type: "Bearer",
        expires_at: result.session.expires_at.iso8601,
        user_id: result.user.id,
        brand: {
          slug: Current.brand.slug,
          name: Current.brand.name
        }
      }, status: :created
    else
      render_error(result.error)
    end
  end

  private

  def phone_params
    params.permit(:phone)
  end

  def verify_params
    params.permit(:phone, :code, :device_name)
  end

  def render_error(error, retry_after: nil)
    case error
    when :brand_required
      render json: { error: "brand_required" }, status: :not_found
    when :auth_method_unavailable
      render json: { error: "auth_method_unavailable" }, status: :not_found
    when :invalid_phone
      render json: { error: "invalid_phone" }, status: :unprocessable_entity
    when :rate_limited
      response.set_header("Retry-After", retry_after.to_s) if retry_after.present?
      render json: { error: "rate_limited" }, status: :too_many_requests
    else
      render json: { error: "invalid_code" }, status: :unauthorized
    end
  end
end
