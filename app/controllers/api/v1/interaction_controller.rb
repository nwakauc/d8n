class Api::V1::InteractionController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_platform_capability!
  before_action :authorize_interaction_access!

  private

  def authorize_interaction_access!
    Identity::InteractionAccess.authorize!(session: Current.session, brand: Current.brand)
  rescue Identity::InteractionAccess::IdentifierVerificationRequired
    render json: { error: "identifier_verification_required" }, status: :forbidden
  end
end
