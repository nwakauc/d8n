class Api::V1::ProfilePreferencesController < ApplicationController
  before_action :authenticate_user!
  before_action -> { enforce_rate_limit!(:profile_write) }, only: :update

  def show
    preference = Profiles::CurrentPreferences.find(user: Current.user, brand: Current.brand)
    return render json: { preferences: nil }, status: :ok if preference.blank?

    render json: { preferences: preference_payload(preference) }
  end

  def update
    preference = Profiles::CurrentPreferences.upsert!(
      user: Current.user,
      brand: Current.brand,
      attributes: preference_params
    )

    render json: { preferences: preference_payload(preference) }, status: :ok
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: "invalid_preferences", details: e.record.errors.to_hash }, status: :unprocessable_entity
  rescue ActiveRecord::RecordNotFound
    render json: { error: "profile_required" }, status: :forbidden
  end

  private

  def preference_params
    params.permit(
      :min_age,
      :max_age,
      :max_distance_km,
      :country,
      :relationship_intent,
      interested_in: []
    )
  end

  def preference_payload(preference)
    {
      id: preference.id,
      profile_id: preference.profile.public_id,
      brand: {
        slug: preference.brand.slug,
        name: preference.brand.name
      },
      min_age: preference.min_age,
      max_age: preference.max_age,
      interested_in: preference.interested_in,
      max_distance_km: preference.max_distance_km,
      country: preference.country,
      relationship_intent: preference.relationship_intent
    }
  end
end
