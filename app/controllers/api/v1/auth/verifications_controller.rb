class Api::V1::Auth::VerificationsController < ApplicationController
  before_action :authenticate_user!
  requires_platform_contract
  before_action :authorize_verification_capability!

  def create
    result = Identity::VerificationRequester.call(
      user: Current.user,
      brand: Current.brand,
      kind: verification_params[:kind],
      ip_address: request.remote_ip,
      user_agent: request.user_agent
    )

    if result.success?
      render json: {
        message: "If this identifier can receive D8N codes, a code has been sent.",
        resend_available_in: result.retry_after || 0,
        expires_at: result.expires_at&.iso8601
      },
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
      render_verification_error(result.error)
    end
  end

  private

  def verification_params
    params.permit(:kind, :code)
  end

  def authorize_verification_capability!
    capability = {
      "email" => "verify.contact.email",
      "phone" => "verify.contact.phone"
    }.fetch(verification_params[:kind], nil)
    return if capability.nil?

    D8n::Platform::CapabilityAccess.authorize!(
      contract: Current.platform_contract,
      capability:
    )
  rescue D8n::Platform::CapabilityAccess::NotConfigured => e
    render json: { error: e.code }, status: :not_found
  end

  def render_request_error(result)
    case result.error
    when :invalid_kind
      render json: { error: "invalid_kind" }, status: :unprocessable_entity
    when :verification_resend_too_soon, :verification_rate_limited
      response.set_header("Retry-After", result.retry_after.to_s)
      render json: { error: result.error.to_s }, status: :too_many_requests
    else
      render json: { error: "delivery_unavailable" }, status: :service_unavailable
    end
  end

  def render_verification_error(error)
    status = case error
    when :verification_code_expired then :gone
    when :verification_code_used then :conflict
    when :verification_attempts_exhausted then :too_many_requests
    else :unauthorized
    end
    render json: { error: error.to_s }, status:
  end
end
