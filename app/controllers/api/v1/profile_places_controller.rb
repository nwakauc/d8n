class Api::V1::ProfilePlacesController < ApplicationController
  requires_platform_capability "profile.location.place_selection"

  before_action :authenticate_user!
  requires_platform_contract
  before_action :authorize_platform_capability!

  def update
    location = Profiles::CurrentPlace.select!(
      user: Current.user, brand: Current.brand, place_id: params[:place_id],
      country_codes: Current.platform_contract.place_country_codes
    )
    render json: { location: location_payload(location) }
  rescue Profiles::CurrentPlace::InvalidPlace
    render json: { error: "invalid_place" }, status: :unprocessable_entity
  rescue ActiveRecord::RecordNotFound
    render json: { error: "profile_required" }, status: :forbidden
  end

  private

  def location_payload(location)
    {
      configured: true,
      accuracy_meters: location.accuracy_meters,
      source: location.source,
      captured_at: location.captured_at.iso8601,
      place: {
        id: location.place.id,
        name: location.place.name,
        display_path: location.place.display_path
      }
    }
  end
end
