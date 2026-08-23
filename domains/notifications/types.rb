module Notifications
  module Types
    Definition = Data.define(:code, :title, :body, :email_subject, :allowed_payload_keys, :allowed_brand_slugs)

    DEFINITIONS = {
      "dateza.welcome" => Definition.new(
        code: "dateza.welcome",
        title: "Welcome to DateZA",
        body: "Your account is ready. Complete your profile and start meeting people worth meeting.",
        email_subject: "Welcome to DateZA",
        allowed_payload_keys: [],
        allowed_brand_slugs: %w[ dateza ]
      )
    }.freeze

    def self.fetch(code)
      DEFINITIONS.fetch(code)
    end

    def self.validate_payload(notification_type:, payload:, brand: nil)
      definition = DEFINITIONS[notification_type]
      return [ "has an unsupported notification type" ] unless definition
      return [ "must be an object" ] unless payload.is_a?(Hash)
      return [ "is not supported for this brand" ] if brand && !definition.allowed_brand_slugs.include?(brand.slug)

      unknown = payload.stringify_keys.keys - definition.allowed_payload_keys
      unknown.empty? ? [] : [ "contains unsupported fields" ]
    end
  end
end
