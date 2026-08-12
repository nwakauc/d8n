class Api::V1::ProfileController < ApplicationController
  before_action :authenticate_user!

  def show
    profile = Profiles::CurrentProfile.find(user: Current.user, brand: Current.brand)
    return render json: { profile: nil }, status: :ok if profile.blank?

    render json: { profile: profile_payload(profile) }
  end

  def update
    profile = Profiles::CurrentProfile.upsert!(
      user: Current.user,
      brand: Current.brand,
      attributes: profile_params
    )

    render json: { profile: profile_payload(profile) }, status: :ok
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: "invalid_profile", details: e.record.errors.to_hash }, status: :unprocessable_entity
  rescue ActiveRecord::RecordNotFound
    render json: { error: "brand_membership_required" }, status: :forbidden
  end

  private

  def profile_params
    params.permit(:display_name, :bio, :birthdate, :gender, :visibility)
  end

  def profile_payload(profile)
    {
      id: profile.id,
      brand: {
        slug: profile.brand.slug,
        name: profile.brand.name
      },
      display_name: profile.display_name,
      bio: profile.bio,
      birthdate: profile.birthdate&.iso8601,
      gender: profile.gender,
      status: profile.status,
      visibility: profile.visibility,
      completion: completion_payload(profile)
    }
  end

  def completion_payload(profile)
    completion = Profiles::Completion.call(profile:)

    {
      complete: completion.complete?,
      percent: completion.percent,
      missing: completion.missing.map(&:to_s)
    }
  end
end
