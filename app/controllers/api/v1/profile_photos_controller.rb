class Api::V1::ProfilePhotosController < ApplicationController
  before_action :ensure_profile_photos_enabled!
  before_action :authenticate_user!
  before_action -> { enforce_rate_limit!(:media_upload_intent) }, only: :create_upload
  before_action -> { enforce_rate_limit!(:media_attach) }, only: :create
  before_action -> { enforce_rate_limit!(:profile_write) }, only: :reorder
  before_action :set_active_storage_url_options, only: %i[index create create_upload reorder]

  def index
    photos = Profiles::PhotoLibrary.list(user: Current.user, brand: Current.brand)

    render json: { photos: owner_photo_payloads(photos) }
  end

  # Control plane: authorize the caller and return a short-lived presigned PUT so
  # the client can upload bytes directly to private R2. D8N allocates the object
  # identity; the client never sees R2 credentials or chooses the object key.
  def create_upload
    intent = Profiles::PhotoUpload.create_intent(
      user: Current.user,
      brand: Current.brand,
      filename: upload_params[:filename],
      byte_size: upload_params.fetch(:byte_size),
      checksum: upload_params.fetch(:checksum),
      content_type: upload_params.fetch(:content_type)
    )

    render json: { upload: intent }, status: :created
  rescue ActionController::ParameterMissing
    render json: { error: "upload_parameters_required" }, status: :unprocessable_entity
  rescue Profiles::PhotoUpload::ProfileRequired
    render json: { error: "profile_required" }, status: :forbidden
  rescue Profiles::PhotoUpload::InvalidContentType
    render json: {
      error: "unsupported_content_type",
      allowed_content_types: Profiles::PhotoUpload::ALLOWED_CONTENT_TYPES
    }, status: :unprocessable_entity
  rescue Profiles::PhotoUpload::InvalidSize
    render json: { error: "invalid_byte_size", byte_size_limit: Profiles::PhotoUpload::MAX_FILE_SIZE },
      status: :unprocessable_entity
  rescue Profiles::PhotoUpload::InvalidUpload
    render json: { error: "checksum_required" }, status: :unprocessable_entity
  rescue Profiles::PhotoUpload::LimitReached => e
    render json: { error: "profile_photo_limit_reached", max_count: e.max_count }, status: :unprocessable_entity
  end

  # Data plane completion: attach a verified, already-uploaded object to the
  # authenticated owner's profile.
  def create
    photo = Profiles::PhotoUpload.attach!(
      user: Current.user,
      brand: Current.brand,
      signed_id: attach_params.fetch(:signed_id),
      position: attach_params[:position]
    )

    photos = Profiles::PhotoLibrary.list(user: Current.user, brand: Current.brand)
    render json: { photo: owner_photo_payloads(photos).find { |item| item.fetch(:id) == photo.id } }, status: :created
  rescue ActionController::ParameterMissing
    render json: { error: "signed_id_required" }, status: :unprocessable_entity
  rescue Profiles::PhotoUpload::ProfileRequired
    render json: { error: "profile_required" }, status: :forbidden
  rescue Profiles::PhotoUpload::InvalidUpload
    render json: { error: "invalid_upload" }, status: :unprocessable_entity
  rescue Profiles::PhotoUpload::AlreadyAttached
    render json: { error: "upload_already_used" }, status: :unprocessable_entity
  rescue Profiles::PhotoUpload::MissingObject
    render json: { error: "upload_not_found" }, status: :unprocessable_entity
  rescue Profiles::PhotoUpload::InvalidObject
    render json: { error: "invalid_image" }, status: :unprocessable_entity
  rescue Profiles::PhotoUpload::InvalidSize
    render json: { error: "invalid_byte_size", byte_size_limit: Profiles::PhotoUpload::MAX_FILE_SIZE },
      status: :unprocessable_entity
  rescue Profiles::PhotoUpload::LimitReached => e
    render json: { error: "profile_photo_limit_reached", max_count: e.max_count }, status: :unprocessable_entity
  rescue Profiles::PhotoOrder::InvalidOrder
    render json: { error: "invalid_photo_position" }, status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: "invalid_photo", details: e.record.errors.to_hash }, status: :unprocessable_entity
  end

  def destroy
    photo = Profiles::PhotoLibrary.soft_delete!(user: Current.user, brand: Current.brand, id: params[:id])

    render json: { photo: photo_payload(photo) }
  rescue ActiveRecord::RecordNotFound
    render json: { error: "not_found" }, status: :not_found
  end

  def reorder
    photos = Profiles::PhotoOrder.reorder!(
      user: Current.user,
      brand: Current.brand,
      ids: params[:photo_ids]
    )

    render json: { photos: owner_photo_payloads(photos) }
  rescue ActiveRecord::RecordNotFound
    render json: { error: "not_found" }, status: :not_found
  rescue Profiles::PhotoOrder::InvalidOrder
    render json: { error: "invalid_photo_order" }, status: :unprocessable_entity
  end

  private

  def ensure_profile_photos_enabled!
    return if Rails.configuration.x.profile_photos_enabled

    render json: { error: "not_found" }, status: :not_found
  end

  def upload_params
    params.permit(:filename, :byte_size, :checksum, :content_type)
  end

  def attach_params
    params.permit(:signed_id, :position)
  end

  def photo_payload(photo)
    {
      id: photo.id,
      profile_id: photo.profile.public_id,
      position: photo.position,
      primary: false,
      status: photo.status,
      visibility: photo.visibility,
      processing_state: photo.processing_state,
      deleted_at: photo.deleted_at&.iso8601,
      image: image_payload(photo)
    }
  end

  def owner_photo_payloads(photos)
    photos.each_with_index.map do |photo, index|
      photo_payload(photo).merge(primary: index.zero?)
    end
  end

  # Private media is served through a short-lived signed retrieval URL straight
  # from R2 — never a permanent public object path, and never proxied through
  # Puma. The owner sees the safe display derivative once processing is ready and
  # otherwise their own raw upload while it is still pending.
  def image_payload(photo)
    attachment = owner_attachment(photo)
    return if attachment.nil?

    blob = attachment.blob
    {
      filename: blob.filename.to_s,
      content_type: blob.content_type,
      byte_size: blob.byte_size,
      url: attachment.url(expires_in: Profiles::PhotoUpload::RETRIEVAL_URL_EXPIRES_IN),
      url_expires_in: Profiles::PhotoUpload::RETRIEVAL_URL_EXPIRES_IN.to_i
    }
  end

  def owner_attachment(photo)
    return photo.display_image if photo.processing_ready? && photo.display_image.attached?
    return photo.image if photo.image.attached?

    nil
  end
end
