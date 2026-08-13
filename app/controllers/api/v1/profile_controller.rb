class Api::V1::ProfileController < ApplicationController
  before_action :authenticate_user!

  def show
    profile = Profiles::CurrentProfile.find(user: Current.user, brand: Current.brand)
    return render json: { profile: nil }, status: :ok if profile.blank?

    render json: { profile: Profiles::OwnerSerializer.call(profile:) }
  end

  def update
    profile = Profiles::CurrentProfile.upsert!(
      user: Current.user,
      brand: Current.brand,
      attributes: profile_params
    )

    render json: { profile: Profiles::OwnerSerializer.call(profile:) }, status: :ok
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: "invalid_profile", details: e.record.errors.to_hash }, status: :unprocessable_entity
  rescue ActiveRecord::RecordNotFound
    render json: { error: "brand_membership_required" }, status: :forbidden
  end

  private

  def profile_params
    params.permit(
      :display_name, :bio, :birthdate, :gender, :visibility,
      :country_code, :city, :occupation, :height_cm, :body_type,
      :smoking, :drinking, :fitness,
      languages_spoken: []
    )
  end
end
