class Api::V1::DiscoveryController < ApplicationController
  before_action :authenticate_user!
  before_action :set_active_storage_url_options, only: :index

  def index
    result = Matching::Discovery.call(
      user: Current.user,
      brand: Current.brand,
      cursor: params[:cursor],
      limit: params[:limit]
    )
    render json: {
      profiles: result.profiles.map { |profile| Matching::CandidateSerializer.call(profile:, strategy: result.strategy) },
      next_cursor: result.next_cursor
    }
  rescue Matching::Discovery::ViewerIneligible
    render json: { error: "discoverable_profile_required" }, status: :forbidden
  rescue Matching::Discovery::InvalidLimit
    render json: { error: "invalid_limit" }, status: :unprocessable_entity
  rescue Matching::Cursor::Invalid
    render json: { error: "invalid_cursor" }, status: :unprocessable_entity
  rescue Matching::StrategyRegistry::UnsupportedBrand
    render json: { error: "matching_not_configured" }, status: :not_found
  end
end
