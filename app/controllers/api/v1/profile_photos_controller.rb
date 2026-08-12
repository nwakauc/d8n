class Api::V1::ProfilePhotosController < ApplicationController
  before_action :authenticate_user!

  def index
    photos = Profiles::PhotoLibrary.list(user: Current.user, brand: Current.brand)

    render json: { photos: photos.map { |photo| photo_payload(photo) } }
  end

  def create
    photo = Profiles::PhotoLibrary.add!(
      user: Current.user,
      brand: Current.brand,
      image: photo_params.fetch(:image),
      position: photo_params[:position]
    )

    render json: { photo: photo_payload(photo) }, status: :created
  rescue ActionController::ParameterMissing
    render json: { error: "image_required" }, status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: "invalid_photo", details: e.record.errors.to_hash }, status: :unprocessable_entity
  rescue ActiveRecord::RecordNotFound
    render json: { error: "profile_required" }, status: :forbidden
  end

  def destroy
    photo = Profiles::PhotoLibrary.soft_delete!(user: Current.user, brand: Current.brand, id: params[:id])

    render json: { photo: photo_payload(photo) }
  rescue ActiveRecord::RecordNotFound
    render json: { error: "not_found" }, status: :not_found
  end

  private

  def photo_params
    params.permit(:image, :position)
  end

  def photo_payload(photo)
    {
      id: photo.id,
      profile_id: photo.profile_id,
      position: photo.position,
      status: photo.status,
      visibility: photo.visibility,
      deleted_at: photo.deleted_at&.iso8601,
      image: image_payload(photo)
    }
  end

  def image_payload(photo)
    return unless photo.image.attached?

    {
      filename: photo.image.filename.to_s,
      content_type: photo.image.content_type,
      byte_size: photo.image.byte_size,
      url: Rails.application.routes.url_helpers.rails_blob_path(photo.image, only_path: true)
    }
  end
end
