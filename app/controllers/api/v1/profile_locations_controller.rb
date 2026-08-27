class Api::V1::ProfileLocationsController < ApplicationController
  before_action :authenticate_user!

  # Authoritative owner readback of the same ProfileLocation row every other
  # location path (PUT here, PUT /profile/place, Matching::EligibilityScope)
  # reads and writes. No profile / no ProfileLocation / a suspended profile /
  # a not-yet-onboarded member all resolve to the same stable "unconfigured"
  # response rather than a 403/404 — matching GET /profile/preferences'
  # existing null-safe convention for owner subresource reads.
  def show
    location = Profiles::CurrentLocation.find(user: Current.user, brand: Current.brand)

    render json: { location: detailed_location_payload(location) }
  end

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

  # Never latitude/longitude: the owner-facing UI needs to display and edit a
  # dating AREA, not a precise point, and Matching (Matching::EligibilityScope)
  # is the only consumer that needs the raw coordinates — it reads
  # ProfileLocation directly and never goes through this endpoint.
  def detailed_location_payload(location)
    return { configured: false } if location.blank?

    {
      configured: true,
      source: location.source,
      captured_at: location.captured_at.iso8601,
      accuracy_meters: location.accuracy_meters,
      place: location.place && place_payload(location.place)
    }
  end

  def place_payload(place)
    {
      id: place.id,
      kind: place.kind,
      name: place.name,
      code: place.code,
      country_code: place.country_code,
      display_path: place.display_path
    }
  end
end
