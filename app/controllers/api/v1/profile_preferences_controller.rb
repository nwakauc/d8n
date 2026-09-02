class Api::V1::ProfilePreferencesController < ApplicationController
  before_action :authenticate_user!
  before_action -> { enforce_rate_limit!(:profile_write) }, only: :update

  def show
    preference = Profiles::CurrentPreferences.find(user: Current.user, brand: Current.brand)
    return render json: { preferences: nil }, status: :ok if preference.blank?

    render json: { preferences: preference_payload(preference) }
  end

  def update
    field_policy.validate_preference_write!(params.keys)
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
  rescue Profiles::FieldPolicy::UnsupportedFields => e
    render json: { error: "invalid_preference_fields", details: { fields: e.fields } }, status: :unprocessable_entity
  end

  private

  def field_policy
    @field_policy ||= Profiles::FieldPolicy.new(brand: Current.brand)
  end

  # Only the preference scalars the resolved brand contract enables are
  # accepted; the same source (brand.profile_completion_requirements) that
  # Profiles::Configuration advertises to the client.
  def preference_params
    filters = field_policy.writable_preference_fields.map do |field|
      field == "interested_in" ? { interested_in: [] } : field.to_sym
    end
    params.permit(*filters)
  end

  def preference_payload(preference)
    envelope = {
      id: preference.id,
      profile_id: preference.profile.public_id,
      brand: {
        slug: preference.brand.slug,
        name: preference.brand.name
      }
    }

    values = field_policy.writable_preference_fields.index_with do |field|
      preference.public_send(field)
    end.symbolize_keys

    envelope.merge(values)
  end
end
