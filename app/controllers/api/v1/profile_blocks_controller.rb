class Api::V1::ProfileBlocksController < ApplicationController
  before_action :authenticate_user!

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
end
