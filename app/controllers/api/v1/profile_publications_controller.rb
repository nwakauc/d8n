class Api::V1::ProfilePublicationsController < ApplicationController
  before_action :authenticate_user!

  def create
    profile = Profiles::Publication.activate!(user: Current.user, brand: Current.brand)
    render json: { profile: Profiles::OwnerSerializer.call(profile:) }
  rescue ActiveRecord::RecordNotFound
    render json: { error: "profile_required" }, status: :forbidden
  rescue Profiles::Publication::Incomplete => e
    render json: {
      error: "profile_incomplete",
      completion: {
        percent: e.completion.percent,
        missing: e.completion.missing.map(&:to_s)
      }
    }, status: :unprocessable_entity
  rescue Profiles::Publication::Unavailable
    render json: { error: "profile_unavailable" }, status: :forbidden
  end

  def destroy
    profile = Profiles::Publication.deactivate!(user: Current.user, brand: Current.brand)
    render json: { profile: Profiles::OwnerSerializer.call(profile:) }
  rescue ActiveRecord::RecordNotFound
    render json: { error: "profile_required" }, status: :forbidden
  end
end
