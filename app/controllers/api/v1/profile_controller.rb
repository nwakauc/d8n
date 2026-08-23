class Api::V1::ProfileController < ApplicationController
  before_action :authenticate_user!
  before_action -> { enforce_rate_limit!(:profile_write) }, only: :update

  def show
    profile = Profiles::CurrentProfile.find(user: Current.user, brand: Current.brand)

    render json: profile_payload(profile)
  end

  def update
    profile = Profiles::CurrentProfile.upsert!(
      user: Current.user,
      brand: Current.brand,
      attributes: profile_params
    )

    render json: profile_payload(profile), status: :ok
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: "invalid_profile", details: e.record.errors.to_hash }, status: :unprocessable_entity
  rescue ActiveRecord::RecordNotFound
    render json: { error: "brand_membership_required" }, status: :forbidden
  end

  private

  def profile_payload(profile)
    {
      profile: profile && Profiles::OwnerSerializer.call(profile:),
      onboarding: Profiles::OnboardingStatus.call(user: Current.user, brand: Current.brand)
    }
  end

  def profile_params
    params.permit(
      :first_name, :last_name, :display_name, :bio, :birthdate, :gender, :pronouns, :visibility,
      :country_code, :city, :occupation, :job_title, :company_name,
      :school_or_institution, :looking_for_text, :children_count,
      :height_cm, :body_type, :smoking, :drinking, :fitness,
      languages_spoken: [],
      languages: [ :code, :proficiency, :primary ]
    )
  end
end
