class Api::V1::DiscoveryController < ApplicationController
  before_action :authenticate_user!
  requires_platform_contract
  before_action :authorize_discovery_surface!
  before_action -> { enforce_rate_limit!(:discovery) }, only: :index
  before_action :set_active_storage_url_options, only: :index

  def index
    result = Matching::Discovery.call(
      user: Current.user,
      brand: Current.brand,
      cursor: params[:cursor],
      limit: params[:limit],
      mode: params[:mode],
      facet_params: request.query_parameters,
      surface: @discovery_surface
    )
    statuses = Profiles::StatusFields.call(
      viewer: result.viewer, profiles: result.profiles, eligibility_policy: result.eligibility_policy
    )
    decorations = D8n::Platform::ResponseDecorations.call(
      viewer: result.viewer, profiles: result.profiles, decorators: result.decorators
    )
    payload = {
      profiles: result.profiles.map do |profile|
        status = statuses.fetch(profile.id, {}).merge(decorations.fetch(profile.id, {}))
        if result.compatibility_by_profile
          Matching::CandidateSerializer.call(
            profile:, strategy: result.strategy, status:,
            compatibility: result.compatibility_by_profile.fetch(profile.id)
          )
        else
          Matching::CandidateSerializer.call(profile:, strategy: result.strategy, status:)
        end
      end,
      next_cursor: result.next_cursor
    }
    payload[:selection] = result.selection if result.selection
    render json: payload
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

  private

  def authorize_discovery_surface!
    @discovery_surface = Matching::StrategyRegistry.surface_for(brand: Current.brand, mode: params[:mode])
    D8n::Platform::CapabilityAccess.authorize!(
      contract: Current.platform_contract,
      capability: @discovery_surface.delivery_capability_key,
      surface: @discovery_surface.key
    )
  rescue Matching::StrategyRegistry::UnsupportedMode
    render json: { error: "invalid_mode" }, status: :unprocessable_entity
  rescue Matching::StrategyRegistry::UnsupportedBrand, D8n::Platform::CapabilityAccess::NotConfigured
    render json: { error: "matching_not_configured" }, status: :not_found
  end
end
