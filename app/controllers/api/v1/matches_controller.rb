class Api::V1::MatchesController < ApplicationController
  before_action :authenticate_user!

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

  private

  def match_payload(match:, viewer:)
    {
      id: match.public_id,
      matched_at: match.created_at.iso8601,
      profile: Profiles::PublicSerializer.call(profile: match.other_profile(viewer))
    }
  end
end
