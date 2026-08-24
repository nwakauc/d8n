class Api::V1::ProfilePassesController < Api::V1::InteractionController
  requires_platform_capability "match.interaction.pass"

  before_action -> { enforce_rate_limit!(:pass_profile) }, only: :create

  def create
    result = Matching::PassProfile.call(
      user: Current.user,
      brand: Current.brand,
      target_public_id: params[:profile_id]
    )

    render json: { passed: true, created: result.created }, status: result.created ? :created : :ok
  rescue Matching::InteractionError => e
    status = e.code == :profile_unavailable ? :not_found : :conflict
    render json: { error: e.code }, status:
  rescue Matching::StrategyRegistry::UnsupportedBrand
    render json: { error: "matching_not_configured" }, status: :not_found
  end
end
