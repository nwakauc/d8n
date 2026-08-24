module Notifications
  # The small, explicit boundary where a product event becomes a product
  # notification. Brand differences live here instead of provider jobs or auth.
  module Policy
    def self.handles?(brand:, event_type:)
      notification_configuration(brand:).plan_for(event_type).present?
    rescue D8n::Platform::BrandRegistry::UnsupportedBrand
      false
    end

    def self.plan_for(event)
      notification_configuration(brand: event.brand).plan_for(event.event_type)
    rescue D8n::Platform::BrandRegistry::UnsupportedBrand
      nil
    end

    def self.channel_allowed?(membership:, category:)
      preference = NotificationPreference.kept.find_by(brand_membership: membership)
      preference.nil? || preference.allows?(category)
    end

    def self.notification_configuration(brand:)
      D8n::Platform::BrandRegistry.fetch(brand:).notifications
    end
    private_class_method :notification_configuration
  end
end
