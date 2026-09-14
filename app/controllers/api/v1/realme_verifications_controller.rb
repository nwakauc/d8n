class Api::V1::RealmeVerificationsController < ApplicationController
  before_action :authenticate_user!
  before_action -> { enforce_rate_limit!(:media_upload_intent) }, only: :create_upload
  before_action -> { enforce_rate_limit!(:media_attach) }, only: :create
  before_action :set_active_storage_url_options, only: %i[create_upload create]

  def create_upload
    intent = Identity::RealmeSubmission.create_intent(
      user: Current.user, brand: Current.brand,
      check_type: upload_params.fetch(:check_type),
      filename: upload_params[:filename],
      byte_size: upload_params.fetch(:byte_size),
      checksum: upload_params.fetch(:checksum),
      content_type: upload_params.fetch(:content_type)
    )

    render json: { upload: intent }, status: :created
  rescue ActionController::ParameterMissing
    render json: { error: "upload_parameters_required" }, status: :unprocessable_entity
  rescue *upload_error_classes => e
    render_upload_error(e)
  end

  def create
    assertion = Identity::RealmeSubmission.attach!(
      user: Current.user, brand: Current.brand,
      check_type: attach_params.fetch(:check_type),
      signed_id: attach_params.fetch(:signed_id)
    )

    render json: { assertion: assertion_payload(assertion) }, status: :created
  rescue ActionController::ParameterMissing
    render json: { error: "upload_parameters_required" }, status: :unprocessable_entity
  rescue *upload_error_classes => e
    render_upload_error(e)
  end

  private

  def upload_error_classes
    [
      Identity::RealmeSubmission::ProfileRequired, Identity::RealmeSubmission::InvalidCheckType,
      Identity::RealmeSubmission::InvalidContentType, Identity::RealmeSubmission::InvalidSize,
      Identity::RealmeSubmission::InvalidUpload, Identity::RealmeSubmission::PendingSubmissionExists,
      Identity::RealmeSubmission::MissingObject, Identity::RealmeSubmission::InvalidObject
    ]
  end

  def render_upload_error(error)
    case error
    when Identity::RealmeSubmission::ProfileRequired
      render json: { error: "profile_required" }, status: :forbidden
    when Identity::RealmeSubmission::InvalidCheckType
      render json: { error: "unsupported_check_type", allowed_check_types: Identity::RealmeSubmission::CHECK_TYPES },
        status: :unprocessable_entity
    when Identity::RealmeSubmission::InvalidContentType
      render json: { error: "unsupported_content_type" }, status: :unprocessable_entity
    when Identity::RealmeSubmission::InvalidSize
      render json: { error: "invalid_byte_size" }, status: :unprocessable_entity
    when Identity::RealmeSubmission::PendingSubmissionExists
      render json: { error: "verification_already_pending" }, status: :unprocessable_entity
    when Identity::RealmeSubmission::MissingObject
      render json: { error: "upload_not_found" }, status: :unprocessable_entity
    when Identity::RealmeSubmission::InvalidObject
      render json: { error: "invalid_upload" }, status: :unprocessable_entity
    else
      render json: { error: "invalid_upload" }, status: :unprocessable_entity
    end
  end

  def assertion_payload(assertion)
    { check_type: assertion.check_type, status: assertion.status, submitted_at: assertion.submitted_at&.iso8601 }
  end

  def upload_params
    params.permit(:check_type, :filename, :byte_size, :checksum, :content_type)
  end

  def attach_params
    params.permit(:check_type, :signed_id)
  end
end
