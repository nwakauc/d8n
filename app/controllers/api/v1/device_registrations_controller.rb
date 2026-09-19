class Api::V1::DeviceRegistrationsController < ApplicationController
  before_action :authenticate_user!
  before_action -> { enforce_rate_limit!(:device_registration, installation_id: params.dig(:device_registration, :installation_id)) }, only: :create
  before_action -> { enforce_rate_limit!(:device_registration, installation_id: params[:installation_id]) }, only: :destroy

  def create
    result = Notifications::DeviceRegistrar.register!(
      brand: Current.brand,
      user: Current.user,
      membership: current_membership,
      **registration_params.to_h.symbolize_keys
    )

    render json: { device_registration: response_payload(result.registration) },
      status: result.created? ? :created : :ok
  rescue ActionController::ParameterMissing
    render json: { error: "device_registration_parameters_required" }, status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: "invalid_device_registration", details: e.record.errors.to_hash }, status: :unprocessable_entity
  rescue ArgumentError
    render json: { error: "device_registration_parameters_required" }, status: :unprocessable_entity
  end

  def destroy
    registration = Notifications::DeviceRegistrar.revoke!(
      brand: Current.brand,
      user: Current.user,
      membership: current_membership,
      installation_id: params.require(:installation_id)
    )

    render json: { device_registration: response_payload(registration) }, status: :ok
  rescue ActionController::ParameterMissing
    render json: { error: "installation_id_required" }, status: :unprocessable_entity
  end

  private

  def current_membership
    @current_membership ||= BrandMembership.kept.active.find_by!(brand: Current.brand, user: Current.user)
  end

  def registration_params
    params.require(:device_registration).permit(:installation_id, :token, :platform, :device_name)
  end

  def response_payload(registration)
    return { installation_id: params[:installation_id], enabled: false } unless registration

    {
      id: registration.public_id,
      installation_id: registration.installation_id,
      platform: registration.platform,
      device_name: registration.device_name,
      enabled: registration.enabled,
      last_seen_at: registration.last_seen_at.iso8601
    }
  end
end
