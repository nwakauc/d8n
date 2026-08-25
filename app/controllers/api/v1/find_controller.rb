class Api::V1::FindController < ApplicationController
  requires_platform_capability "discovery.surface.browse", surface: "discovery.find"

  before_action :authenticate_user!
  requires_platform_contract
  before_action :authorize_platform_capability!
  before_action -> { enforce_rate_limit!(:find_profiles) }, only: :index
  before_action :set_active_storage_url_options, only: :index

  def index
    result = Matching::Find::Search.call(
      user: Current.user,
      brand: Current.brand,
      cursor: params[:cursor],
      limit: params[:limit],
      min_age: params[:min_age],
      max_age: params[:max_age],
      max_distance_km: params[:max_distance_km],
      relationship_intent: params[:relationship_intent]
    )
    statuses = Profiles::StatusFields.call(
      viewer: result.viewer, profiles: result.profiles, eligibility_policy: result.eligibility_policy
    )
    decorations = D8n::Platform::ResponseDecorations.call(
      viewer: result.viewer, profiles: result.profiles, decorators: result.decorators
    )
    compatibility_strategy = Matching::StrategyRegistry.compatibility_for(brand: Current.brand)
    compatibility = compatibility_strategy.new(brand: Current.brand, viewer: result.viewer)

    render json: {
      profiles: result.profiles.map do |profile|
        safe_status = statuses.fetch(profile.id, {}).slice(
          :verified, :online, :active_today, :new_here, :last_active_at, :distance_km
        )
        pair_compatibility = compatibility.for_eligible_pair(candidate: profile).public_payload
        Profiles::PublicSerializer.call(profile:).merge(
          safe_status, decorations.fetch(profile.id, {}), compatibility: pair_compatibility
        )
      end,
      next_cursor: result.next_cursor,
      allowance: result.allowance
    }
  rescue Matching::Find::Search::ViewerIneligible
    render json: { error: "discoverable_profile_required" }, status: :forbidden
  rescue Matching::Find::Search::InvalidLimit
    render json: { error: "invalid_limit" }, status: :unprocessable_entity
  rescue Matching::Find::Filter::Invalid
    render json: { error: "invalid_filter" }, status: :unprocessable_entity
  rescue Matching::Find::Cursor::Invalid
    render json: { error: "invalid_cursor" }, status: :unprocessable_entity
  rescue Matching::Find::PolicyRegistry::UnsupportedBrand
    render json: { error: "find_not_configured" }, status: :not_found
  rescue Matching::StrategyRegistry::UnsupportedBrand
    render json: { error: "find_not_configured" }, status: :not_found
  end
end
