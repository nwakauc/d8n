class Api::V1::DiscoveryController < ApplicationController
  before_action :authenticate_user!
  before_action -> { enforce_rate_limit!(:discovery) }, only: :index
  before_action :set_active_storage_url_options, only: :index

  def index
    result = Matching::Discovery.call(
      user: Current.user,
      brand: Current.brand,
      cursor: params[:cursor],
      limit: params[:limit],
      mode: params[:mode],
      vibe: params[:vibe],
      online: params[:online]
    )
    statuses = Profiles::StatusFields.call(viewer: result.viewer, profiles: result.profiles)
    hook_states = Hooks::ViewerStates.call(viewer: result.viewer, profiles: result.profiles)
    render json: {
      profiles: result.profiles.map do |profile|
        status = statuses.fetch(profile.id, {}).merge(hook_state: hook_states.fetch(profile.id, Hooks::ViewerStates::UNAVAILABLE))
        Matching::CandidateSerializer.call(profile:, strategy: result.strategy, status:)
      end,
      next_cursor: result.next_cursor
    }
  rescue Matching::Discovery::ViewerIneligible
    render json: { error: "discoverable_profile_required" }, status: :forbidden
  rescue Matching::Discovery::InvalidLimit
    render json: { error: "invalid_limit" }, status: :unprocessable_entity
  rescue Matching::Cursor::Invalid
    render json: { error: "invalid_cursor" }, status: :unprocessable_entity
  rescue Matching::StrategyRegistry::UnsupportedMode
    render json: { error: "invalid_mode" }, status: :unprocessable_entity
  rescue Matching::FacetFilter::InvalidFilter
    render json: { error: "invalid_filter" }, status: :unprocessable_entity
  rescue Matching::StrategyRegistry::UnsupportedBrand
    render json: { error: "matching_not_configured" }, status: :not_found
  end
end
