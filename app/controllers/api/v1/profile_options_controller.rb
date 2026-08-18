class Api::V1::ProfileOptionsController < ApplicationController
  before_action :authenticate_user!
  before_action -> { enforce_rate_limit!(:profile_write) }, only: :update

  def update
    profile = Profiles::CurrentProfile.find(user: Current.user, brand: Current.brand)
    return render json: { error: "profile_required" }, status: :forbidden if profile.blank?

    Profiles::OptionSelections.replace!(profile:, selections: selections_params)

    render json: { profile: Profiles::OwnerSerializer.call(profile: profile.reload) }
  rescue Profiles::OptionSelections::InvalidSelection => e
    render json: { error: "invalid_profile_options", details: e.details }, status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: "invalid_profile_options", details: e.record.errors.to_hash }, status: :unprocessable_entity
  end

  private

  def selections_params
    value = params[:selections]
    unless value.respond_to?(:to_unsafe_h)
      raise Profiles::OptionSelections::InvalidSelection.new(base: [ "selections must be an object" ])
    end

    value.to_unsafe_h
  end
end
