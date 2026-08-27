class Api::V1::LocationSearchController < ApplicationController
  # Same capability that already gates the Place catalog browse/select paths
  # (GET /places, PUT /profile/place) — search is another way to reach the
  # same underlying Place data, not a separate product surface, so it shares
  # the same brand gate (e.g. HookUs, which has no place_country_codes
  # configured, gets the same 404 capability_not_configured it already does
  # from GET /places).
  requires_platform_capability "profile.location.place_selection"

  before_action :authenticate_user!
  requires_platform_contract
  before_action :authorize_platform_capability!
  before_action -> { enforce_rate_limit!(:location_search) }, only: :index

  def index
    results = Geography::Search.call(brand: Current.brand, query: params[:q])

    render json: { results: results.map { |result| result_payload(result) } }
  rescue Geography::Search::InvalidQuery
    render json: { error: "query_too_short", min_length: Geography::Search::MIN_QUERY_LENGTH },
      status: :unprocessable_entity
  end

  private

  def result_payload(result)
    {
      place_id: result.place_id,
      label: result.label,
      area: result.area,
      city: result.city,
      region: result.region,
      country_code: result.country_code,
      kind: result.kind
    }
  end
end
