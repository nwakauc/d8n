class Api::V1::MatchesController < Api::V1::InteractionController
  requires_platform_capability "match.relationship.list"

  # `unmatch` is a distinct capability from `match.relationship.list` (viewing
  # matches does not imply the ability to end them, and vice versa), so it
  # skips the class-level check and authorizes itself.
  skip_before_action :authorize_platform_capability!, only: :unmatch
  before_action :authorize_unmatch_capability!, only: :unmatch
  before_action :set_active_storage_url_options, only: :index

  def index
    result = Matching::MatchList.call(
      user: Current.user,
      brand: Current.brand,
      cursor: params[:cursor],
      limit: params[:limit]
    )

    render json: {
      matches: result.matches.map { |match| match_payload(match:, viewer: result.viewer) },
      next_cursor: result.next_cursor
    }
  rescue Matching::InteractionError
    render json: { error: "profile_unavailable" }, status: :forbidden
  rescue Matching::MatchList::InvalidLimit
    render json: { error: "invalid_limit" }, status: :unprocessable_entity
  rescue Matching::MatchCursor::Invalid
    render json: { error: "invalid_cursor" }, status: :unprocessable_entity
  end

  # Idempotent: ending an already-ended Match (by a prior unmatch, or by a
  # Block) is a safe no-op and still returns 204, matching
  # DELETE /profiles/:profile_id/block's unconditional idempotent 204.
  def unmatch
    Matching::Unmatch.call(user: Current.user, brand: Current.brand, match_public_id: params[:match_id])

    head :no_content
  rescue Matching::InteractionError => e
    render_unmatch_error(e)
  end

  private

  def match_payload(match:, viewer:)
    {
      id: match.public_id,
      matched_at: match.created_at.iso8601,
      profile: Profiles::PublicSerializer.call(profile: match.other_profile(viewer))
    }
  end

  def authorize_unmatch_capability!
    D8n::Platform::CapabilityAccess.authorize!(
      contract: Current.platform_contract, capability: "match.relationship.unmatch"
    )
  rescue D8n::Platform::CapabilityAccess::NotConfigured => e
    render json: { error: e.code }, status: :not_found
  end

  # `:profile_unavailable` (the viewer's own profile is not currently a valid
  # match member) matches #index's existing 403 for the same underlying
  # Matching::ProfileParticipant.match_member! failure. `:match_unavailable`
  # (unknown, cross-brand, or non-participant match) is 404, mirroring
  # POST /matches/:match_id/conversation's handling of the same
  # addressed-by-id-in-the-URL scenario. Neither leaks which case occurred to
  # a non-participant.
  def render_unmatch_error(error)
    status = error.code == :profile_unavailable ? :forbidden : :not_found
    render json: { error: error.code }, status:
  end
end
