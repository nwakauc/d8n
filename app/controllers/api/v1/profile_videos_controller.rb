class Api::V1::ProfileVideosController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_profile_video_enabled!
  before_action -> { enforce_rate_limit!(:media_upload_intent) }, only: :create_upload
  before_action -> { enforce_rate_limit!(:media_attach) }, only: :create
  before_action -> { enforce_rate_limit!(:profile_write) }, only: :destroy
  before_action :set_active_storage_url_options

  def show
    video = Profiles::VideoLibrary.find(user: Current.user, brand: Current.brand)

    render json: { video: Profiles::VideoLibrary.owner_payload(video) }
  end

  def create_upload
    intent = Profiles::VideoUpload.create_intent(
      user: Current.user, brand: Current.brand,
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
    video = Profiles::VideoUpload.attach!(
      user: Current.user, brand: Current.brand,
      signed_id: attach_params.fetch(:signed_id)
    )

    render json: { video: Profiles::VideoLibrary.owner_payload(video) }, status: :created
  rescue ActionController::ParameterMissing
    render json: { error: "signed_id_required" }, status: :unprocessable_entity
  rescue *upload_error_classes => e
    render_upload_error(e)
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: "invalid_video", details: e.record.errors.to_hash }, status: :unprocessable_entity
  end

  def destroy
    Profiles::VideoLibrary.soft_delete!(user: Current.user, brand: Current.brand, actor: Current.user)
    head :no_content
  rescue ActiveRecord::RecordNotFound
    render json: { error: "not_found" }, status: :not_found
  end

  private

  def ensure_profile_video_enabled!
    D8n::Platform::CapabilityAccess.authorize!(
      contract: D8n::Platform::BrandRegistry.fetch(brand: Current.brand),
      capability: "profile.video"
    )
  rescue D8n::Platform::BrandRegistry::UnsupportedBrand, D8n::Platform::CapabilityAccess::NotConfigured
    render json: { error: "not_found" }, status: :not_found
  end

  def upload_error_classes
    [
      Profiles::VideoUpload::ProfileRequired, Profiles::VideoUpload::NotConfigured,
      Profiles::VideoUpload::InvalidContentType, Profiles::VideoUpload::InvalidSize,
      Profiles::VideoUpload::InvalidUpload, Profiles::VideoUpload::AlreadyAttached,
      Profiles::VideoUpload::InvalidObject, Profiles::VideoUpload::MissingObject
    ]
  end

  def render_upload_error(error)
    case error
    when Profiles::VideoUpload::ProfileRequired
      render json: { error: "profile_required" }, status: :forbidden
    when Profiles::VideoUpload::NotConfigured
      render json: { error: "not_found" }, status: :not_found
    when Profiles::VideoUpload::InvalidContentType
      render json: { error: "unsupported_content_type", allowed_content_types: Profiles::VideoUpload::ALLOWED_CONTENT_TYPES },
        status: :unprocessable_entity
    when Profiles::VideoUpload::InvalidSize
      render json: { error: "invalid_byte_size" }, status: :unprocessable_entity
    when Profiles::VideoUpload::AlreadyAttached
      render json: { error: "video_already_exists" }, status: :unprocessable_entity
    when Profiles::VideoUpload::MissingObject
      render json: { error: "upload_not_found" }, status: :unprocessable_entity
    when Profiles::VideoUpload::InvalidObject
      render json: { error: "invalid_video" }, status: :unprocessable_entity
    else
      render json: { error: "invalid_upload" }, status: :unprocessable_entity
    end
  end

  def upload_params
    params.permit(:filename, :byte_size, :checksum, :content_type)
  end

  def attach_params
    params.permit(:signed_id)
  end
end
