class Api::V1::AccountDeactivationsController < ApplicationController
  requires_platform_capability "id.account.deactivate"
  requires_platform_contract
  before_action :authenticate_user!

  # Explicit confirmation, matching MeController#destroy's pattern, so this can
  # never fire from a bare/mistaken client call — deactivation immediately revokes
  # every session for this brand, including the one making the request.
  CONFIRMATION = "deactivate".freeze

  def create
    return render json: { error: "confirmation_required" }, status: :unprocessable_entity unless confirmed?

    result = Accounts::DeactivateAccount.call(user: Current.user, brand: Current.brand)

    render json: {
      deactivated: true,
      already_deactivated: result.already_deactivated
    }
  rescue ActiveRecord::RecordNotFound
    render json: { error: "account_unavailable" }, status: :not_found
  rescue Accounts::AccountLifecycleError => e
    render json: { error: e.code.to_s }, status: :conflict
  end

  private

  def confirmed?
    params[:confirmation].to_s == CONFIRMATION
  end
end
