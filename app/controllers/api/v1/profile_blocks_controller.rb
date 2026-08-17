class Api::V1::ProfileBlocksController < ApplicationController
  before_action :authenticate_user!

  def index
    blocks = Trust::ListBlockedProfiles.call(user: Current.user, brand: Current.brand)

    render json: { blocks: blocks.map { |block| block_payload(block) } }
  rescue Matching::InteractionError => e
    render json: { error: e.code }, status: :forbidden
  end

  def create
    result = Trust::BlockProfile.call(
      user: Current.user,
      brand: Current.brand,
      target_public_id: params[:profile_id]
    )

    render json: { blocked: true, created: result.created }, status: result.created ? :created : :ok
  rescue Trust::AccessError => e
    render json: { error: e.code }, status: :not_found
  rescue Matching::InteractionError => e
    render json: { error: e.code }, status: :forbidden
  end

  def destroy
    Trust::UnblockProfile.call(
      user: Current.user,
      brand: Current.brand,
      target_public_id: params[:profile_id]
    )

    head :no_content
  rescue Matching::InteractionError => e
    render json: { error: e.code }, status: :forbidden
  end

  private

  # Minimum information needed to recognise and manage a block. The blocked
  # profile's `public_id` is what the unblock endpoint consumes. No private or
  # sensitive account fields are exposed.
  def block_payload(block)
    profile = block.blocked_profile
    {
      profile: { id: profile.public_id, display_name: profile.display_name },
      blocked_at: block.created_at.iso8601
    }
  end
end
