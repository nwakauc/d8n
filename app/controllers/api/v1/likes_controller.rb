class Api::V1::LikesController < Api::V1::InteractionController
  requires_platform_capability "match.interaction.like"

  before_action -> { enforce_rate_limit!(:like_profile) }, only: :create
  before_action :set_active_storage_url_options, only: [ :incoming, :outgoing ]

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

  # People who have liked the viewer and remain a current, actionable
  # relationship state (see Matching::IncomingLikes).
  def incoming
    result = Matching::IncomingLikes.call(
      user: Current.user, brand: Current.brand, cursor: params[:cursor], limit: params[:limit]
    )

    render json: likes_payload(result:, counterpart: :liker_profile)
  rescue Matching::InteractionError
    render json: { error: "profile_unavailable" }, status: :forbidden
  rescue Matching::IncomingLikes::InvalidLimit
    render json: { error: "invalid_limit" }, status: :unprocessable_entity
  rescue Matching::LikesCursor::Invalid
    render json: { error: "invalid_cursor" }, status: :unprocessable_entity
  end

  # People the viewer has liked who remain a current, actionable pre-match
  # relationship state (see Matching::OutgoingLikes).
  def outgoing
    result = Matching::OutgoingLikes.call(
      user: Current.user, brand: Current.brand, cursor: params[:cursor], limit: params[:limit]
    )

    render json: likes_payload(result:, counterpart: :liked_profile)
  rescue Matching::InteractionError
    render json: { error: "profile_unavailable" }, status: :forbidden
  rescue Matching::OutgoingLikes::InvalidLimit
    render json: { error: "invalid_limit" }, status: :unprocessable_entity
  rescue Matching::LikesCursor::Invalid
    render json: { error: "invalid_cursor" }, status: :unprocessable_entity
  end

  private

  def render_interaction_error(error)
    status = error.code == :profile_unavailable ? :not_found : :conflict
    render json: { error: error.code }, status:
  end

  def likes_payload(result:, counterpart:)
    profiles = result.likes.map { |like| like.public_send(counterpart) }
    eligibility_policy = Current.platform_contract.interaction.eligibility_policy
    statuses = Profiles::StatusFields.call(viewer: result.viewer, profiles:, eligibility_policy:)

    {
      likes: result.likes.map do |like|
        profile = like.public_send(counterpart)
        safe_status = statuses.fetch(profile.id, {}).slice(
          :verified, :online, :active_today, :new_here, :last_active_at, :distance_km
        )
        payload = {
          liked_at: like.created_at.iso8601,
          profile: Profiles::PublicSerializer.call(profile:).merge(safe_status)
        }
        compatibility = pair_compatibility(viewer: result.viewer, profile:)
        payload[:profile] = payload[:profile].merge(compatibility:) unless compatibility == :unsupported
        payload
      end,
      next_cursor: result.next_cursor
    }
  end

  # Mirrors Api::V1::ProfilesController#detail_compatibility: use the same
  # visible-pair computation as profile detail (the pair has already passed
  # Matching::VisibilityScope, not full discovery eligibility/ranking), and
  # omit the field entirely for brands with no compatibility strategy (HookUs).
  def pair_compatibility(viewer:, profile:)
    strategy = Current.platform_contract.interaction.compatibility_strategy
    return :unsupported unless strategy&.respond_to?(:for_visible_pair)

    result = strategy.for_visible_pair(brand: Current.brand, viewer:, candidate: profile)
    result.respond_to?(:public_payload) ? result.public_payload : result
  end
end
