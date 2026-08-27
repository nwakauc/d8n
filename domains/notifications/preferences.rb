module Notifications
  # Owner read/write of the existing per-brand-membership NotificationPreference
  # row (see app/models/notification_preference.rb) — the same row
  # Notifications::Policy#channel_allowed? already consults when deciding
  # whether MaterializeEvent creates an email/push NotificationDelivery. This
  # class adds no new persistence; it is the same "no row yet" -> "effective
  # defaults" pattern as Notifications::Policy.channel_allowed? itself
  # (`preference.nil? || preference.allows?(category)`), just surfaced as
  # something a GET can render without writing a row.
  class Preferences
    # Mirrors the model's own column defaults (db/schema.rb) — the row's
    # defaults and this module's defaults must never drift apart, since a GET
    # before any PATCH has to describe exactly what "no row yet" already
    # behaves as for real delivery decisions.
    DEFAULTS = { product_email_enabled: true, push_enabled: true }.freeze

    def self.find(user:, brand:)
      membership = active_membership(user:, brand:)
      return if membership.blank?

      NotificationPreference.kept.find_by(brand_membership: membership)
    end

    def self.upsert!(user:, brand:, attributes:)
      membership = active_membership(user:, brand:)
      raise ActiveRecord::RecordNotFound, "no active brand membership" if membership.blank?

      preference = nil
      membership.with_lock do
        preference = NotificationPreference.kept.find_or_initialize_by(brand_membership: membership)
        preference.brand = brand
        preference.user = user
        preference.assign_attributes(attributes)
        preference.save!
      end
      preference
    end

    # Same membership scoping Notifications::Inbox already uses: a suspended,
    # deactivated, left, or soft-deleted membership behaves exactly like "no
    # membership" here — GET falls back to effective defaults (never an
    # error), matching the rest of the notify.* domain rather than inventing a
    # new availability rule for preferences specifically.
    def self.active_membership(user:, brand:)
      BrandMembership.kept.active.find_by(brand:, user:)
    end
    private_class_method :active_membership
  end
end
