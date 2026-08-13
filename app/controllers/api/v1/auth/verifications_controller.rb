class Api::V1::Auth::VerificationsController < ApplicationController
  before_action :authenticate_user!

  def create
    result = Identity::VerificationRequester.call(
      user: Current.user,
      brand: Current.brand,
      kind: verification_params[:kind],
      ip_address: request.remote_ip,
      user_agent: request.user_agent
    )

    if result.success?
      render json: { message: "If this identifier can receive D8N codes, a code has been sent." },
        status: :accepted
    else
      render_request_error(result)
    end
  end

  def update
    result = Identity::VerificationVerifier.call(
      user: Current.user,
      brand: Current.brand,
      kind: verification_params[:kind],
      code: verification_params[:code],
      ip_address: request.remote_ip,
      user_agent: request.user_agent
    )

    if result.success?
      render json: {
        identifier: {
          kind: result.identity_identifier.kind,
          verified: true
        }
      }
    else
      render json: { error: "invalid_code" }, status: :unauthorized
    end
  end

  private

  def verification_params
    params.permit(:kind, :code)
  end

  def render_request_error(result)
    case result.error
    when :invalid_kind
      render json: { error: "invalid_kind" }, status: :unprocessable_entity
    when :rate_limited
      response.set_header("Retry-After", result.retry_after.to_s)
      render json: { error: "rate_limited" }, status: :too_many_requests
    else
      render json: { error: "delivery_unavailable" }, status: :service_unavailable
    end
  end
end
