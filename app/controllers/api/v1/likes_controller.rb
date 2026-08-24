class Api::V1::LikesController < Api::V1::InteractionController
  requires_platform_capability "match.interaction.like"

  before_action -> { enforce_rate_limit!(:like_profile) }, only: :create

  def create
    result = Matching::LikeProfile.call(
      user: Current.user,
      brand: Current.brand,
      target_public_id: params[:profile_id]
    )

    render json: {
      liked: true,
      matched: result.match.present?,
      match_id: result.match&.public_id,
      created: result.created
    }, status: result.created ? :created : :ok
  rescue Matching::InteractionError => e
    render_interaction_error(e)
  rescue Matching::StrategyRegistry::UnsupportedBrand
    render json: { error: "matching_not_configured" }, status: :not_found
  end

  private

  def render_interaction_error(error)
    status = error.code == :profile_unavailable ? :not_found : :conflict
    render json: { error: error.code }, status:
  end
end
