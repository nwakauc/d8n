class AnalyticsEvent < ApplicationRecord
  belongs_to :brand
  belongs_to :user, optional: true
  belongs_to :profile, optional: true
  belongs_to :session, optional: true

  validates :event_id, :event_type, :occurred_at, :idempotency_key, presence: true
  validate :properties_are_hash
  validate :properties_are_allowlisted
  validates :event_id, :idempotency_key, uniqueness: true
  validate :known_event_type
  validate :brand_scope

  before_update { raise ActiveRecord::ReadOnlyRecord, "analytics events are append-only" }
  before_destroy { raise ActiveRecord::ReadOnlyRecord, "analytics events are append-only" }

  private

  def known_event_type
    errors.add(:event_type, "is not supported") unless Analytics::EventTypes.known?(event_type)
  end

  def properties_are_hash
    errors.add(:properties, "must be an object") unless properties.is_a?(Hash)
  end

  def properties_are_allowlisted
    return unless properties.is_a?(Hash) && Analytics::EventTypes.known?(event_type)

    unknown = properties.stringify_keys.keys - Analytics::EventTypes.allowed_properties(event_type)
    errors.add(:properties, "contains unsupported keys") if unknown.any?
  end

  def brand_scope
    errors.add(:profile, "must belong to the event brand") if profile.present? && profile.brand_id != brand_id
    errors.add(:user, "must match the profile") if profile.present? && user_id.present? && profile.user_id != user_id
    errors.add(:session, "must belong to the event brand") if session.present? && session.brand_id != brand_id
    errors.add(:session, "must match the event user") if session.present? && user_id.present? && session.user_id != user_id
  end
end
