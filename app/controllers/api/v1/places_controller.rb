class Api::V1::PlacesController < ApplicationController
  requires_platform_capability "profile.location.place_selection"

  before_action :authenticate_user!
  requires_platform_contract
  before_action :authorize_platform_capability!

  def index
    places = params[:parent_id].present? ? children_of_param : top_level

    render json: { places: places.map { |place| place_payload(place) } }
  rescue ActiveRecord::RecordNotFound
    render json: { error: "place_not_found" }, status: :not_found
  end

  private

  def top_level
    Current.platform_contract.place_country_codes.flat_map { |code| Place.top_level(country_code: code).to_a }
  end

  def children_of_param
    parent = Place.selectable
      .where(country_code: Current.platform_contract.place_country_codes)
      .find(params[:parent_id])
    Place.children_of(parent).to_a
  end

  def place_payload(place)
    {
      id: place.id,
      kind: place.kind,
      name: place.name,
      code: place.code,
      has_children: place.children.selectable.exists?
    }
  end
end
