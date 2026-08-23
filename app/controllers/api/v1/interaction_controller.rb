class Api::V1::InteractionController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_product_capability!
  before_action :authorize_interaction_access!

  private

  def authorize_product_capability!
    capability = interaction_product_capability
    return if capability.nil?

    Hooks::CapabilityPolicy.authorize!(brand: Current.brand, capability:)
  rescue Hooks::CapabilityPolicy::UnsupportedBrand => e
    render json: { error: e.code }, status: :not_found
  end

  def interaction_product_capability
    nil
  end

  def authorize_interaction_access!
    Identity::InteractionAccess.authorize!(session: Current.session, brand: Current.brand)
  rescue Identity::InteractionAccess::IdentifierVerificationRequired
    render json: { error: "identifier_verification_required" }, status: :forbidden
  end
end
