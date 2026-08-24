class Api::V1::ProfileController < ApplicationController
  before_action :authenticate_user!
  before_action -> { enforce_rate_limit!(:profile_write) }, only: :update

  def show
    profile = Profiles::CurrentProfile.find(user: Current.user, brand: Current.brand)

    render json: profile_payload(profile)
  end

  def update
    field_policy.validate_profile_write!(params.keys)
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
  rescue Profiles::FieldPolicy::UnsupportedFields => e
    render json: { error: "invalid_profile_fields", details: { fields: e.fields } }, status: :unprocessable_entity
  end

  private

  def profile_payload(profile)
    {
      profile: profile && Profiles::OwnerSerializer.call(profile:),
      onboarding: Profiles::OnboardingStatus.call(user: Current.user, brand: Current.brand)
    }
  end

  def field_policy
    @field_policy ||= Profiles::FieldPolicy.new(brand: Current.brand)
  end

  def profile_params
    filters = field_policy.writable_profile_fields.filter_map do |field|
      case field
      when "languages_spoken" then { languages_spoken: [] }
      when "languages" then { languages: [ :code, :proficiency, :primary ] }
      else field.to_sym
      end
    end
    params.permit(*filters)
  end
end
