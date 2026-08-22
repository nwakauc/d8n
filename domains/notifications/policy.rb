module Notifications
  # The small, explicit boundary where a product event becomes a product
  # notification. Brand differences live here instead of provider jobs or auth.
  module Policy
    Plan = Data.define(:notification_type, :email_template)

    EVENT_PLANS = {
      [ "dateza", "membership_registered" ] => Plan.new(
        notification_type: "dateza.welcome",
        email_template: :welcome
      )
    }.freeze

    def self.handles?(brand:, event_type:)
      EVENT_PLANS.key?([ brand.slug, event_type.to_s ])
    end

    def self.plan_for(event)
      EVENT_PLANS[[ event.brand.slug, event.event_type ]]
    end

    def self.channel_allowed?(membership:, category:)
      preference = NotificationPreference.kept.find_by(brand_membership: membership)
      preference.nil? || preference.allows?(category)
    end
  end
end
