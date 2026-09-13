class Api::V1::Community::BaseController < ApplicationController
  requires_platform_capability "community.read"
  requires_platform_contract
  before_action :authenticate_user!
  before_action :authorize_platform_capability!

  rescue_from ::Community::Access::Unavailable, with: :render_unavailable
  rescue_from ActiveRecord::RecordNotFound, with: :render_unavailable
  rescue_from ActiveRecord::RecordInvalid, with: :render_invalid
  rescue_from D8n::Platform::CapabilityAccess::NotConfigured, with: :render_not_configured

  def self.community_writes(*actions)
    before_action :authorize_participation!, only: actions
    before_action -> { enforce_rate_limit!(:community_write) }, only: actions
  end

  private

  def member!
    ::Community::Access.member!(user: Current.user, brand: Current.brand)
  end

  def authorize_participation!
    D8n::Platform::CapabilityAccess.authorize!(
      contract: Current.platform_contract,
      capability: "community.participation"
    )
  end

  def render_unavailable
    render json: { error: "community_resource_unavailable" }, status: :not_found
  end

  def render_invalid(error)
    render json: {
      error: "community_validation_failed",
      fields: error.record.errors.attribute_names
    }, status: :unprocessable_entity
  end

  def render_not_configured(error)
    render json: { error: error.code }, status: :not_found
  end
end
