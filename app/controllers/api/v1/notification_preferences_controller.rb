class Api::V1::NotificationPreferencesController < ApplicationController
  # The request body is a flat { "product_email_enabled": false } object, not
  # a namespaced { "notification_preference": {...} } one — disable Rails'
  # automatic JSON param wrapping so the unknown-key allowlist below only ever
  # sees the caller's actual top-level keys.
  wrap_parameters false

  before_action :authenticate_user!

  PREFERENCE_KEYS = %i[product_email_enabled push_enabled].freeze

  # Owner-only, null-safe like GET /profile/preferences and GET
  # /profile/location: no row yet (or an inactive membership) is a normal 200
  # describing the same effective defaults Notifications::Policy already
  # applies when no NotificationPreference row exists — never an error.
  def show
    preference = Notifications::Preferences.find(user: Current.user, brand: Current.brand)

    render json: { preferences: preference_payload(preference) }
  end

  def update
    preference = Notifications::Preferences.upsert!(
      user: Current.user,
      brand: Current.brand,
      attributes: preference_params
    )

    render json: { preferences: preference_payload(preference) }
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: "invalid_preferences", details: e.record.errors.to_hash }, status: :unprocessable_entity
  rescue ActiveRecord::RecordNotFound
    render json: { error: "membership_required" }, status: :forbidden
  end

  private

  # Strong allowlist of exactly the two columns the model supports today — no
  # SMS/WhatsApp/per-event keys exist because nothing on the delivery side
  # consults them yet (see T4/T5 reports). Strict JSON-boolean only: a string
  # like "true"/"1" is rejected rather than leniently cast, so a client bug
  # can never silently flip a delivery preference into the wrong state.
  def preference_params
    body_keys = params.except(:controller, :action, :format).to_unsafe_h.keys.map(&:to_sym)
    unknown = body_keys - PREFERENCE_KEYS
    raise_invalid!(:base, "contains unsupported preference keys: #{unknown.join(', ')}") if unknown.any?

    permitted = params.permit(*PREFERENCE_KEYS).to_h
    permitted.each do |key, value|
      raise_invalid!(key.to_sym, "must be true or false") unless value.is_a?(TrueClass) || value.is_a?(FalseClass)
    end
    permitted
  end

  def raise_invalid!(attribute, message)
    invalid = NotificationPreference.new
    invalid.errors.add(attribute, message)
    raise ActiveRecord::RecordInvalid, invalid
  end

  def preference_payload(preference)
    return Notifications::Preferences::DEFAULTS.dup if preference.blank?

    { product_email_enabled: preference.product_email_enabled, push_enabled: preference.push_enabled }
  end
end
