class Api::V1::ProfileLocationsController < ApplicationController
  before_action :authenticate_user!

  def update
    location = Profiles::CurrentLocation.upsert!(
      user: Current.user,
      brand: Current.brand,
      attributes: location_params
    )

    render json: { location: location_payload(location) }
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: "invalid_location", details: e.record.errors.to_hash }, status: :unprocessable_entity
  rescue ActiveRecord::RecordNotFound
    render json: { error: "profile_required" }, status: :forbidden
  end

  def destroy
    location = Profiles::CurrentLocation.soft_delete!(user: Current.user, brand: Current.brand)

    render json: { location: location_payload(location) }
  rescue ActiveRecord::RecordNotFound
    render json: { error: "profile_required" }, status: :forbidden
  end

  private

  def location_params
    params.permit(:latitude, :longitude, :accuracy_meters, :captured_at)
  end

  def location_payload(location)
    return { configured: false } if location.blank? || location.deleted_at.present?

    {
      configured: true,
      accuracy_meters: location.accuracy_meters,
      source: location.source,
      captured_at: location.captured_at.iso8601
    }
  end
end
