module Notifications
  module Types
    Definition = Data.define(:code, :title, :body, :email_subject, :allowed_payload_keys)

    DEFINITIONS = {
      "dateza.welcome" => Definition.new(
        code: "dateza.welcome",
        title: "Welcome to DateZA",
        body: "Your account is ready. Complete your profile and start meeting people worth meeting.",
        email_subject: "Welcome to DateZA",
        allowed_payload_keys: []
      )
    }.freeze

    def self.fetch(code)
      DEFINITIONS.fetch(code)
    end

    def self.validate_payload(notification_type:, payload:, brand: nil)
      definition = DEFINITIONS[notification_type]
      return [ "has an unsupported notification type" ] unless definition
      return [ "must be an object" ] unless payload.is_a?(Hash)
      return [ "is not supported for this brand" ] if brand && !allowed_for_brand?(brand:, notification_type:)

      unknown = payload.stringify_keys.keys - definition.allowed_payload_keys
      unknown.empty? ? [] : [ "contains unsupported fields" ]
    end

    def self.allowed_for_brand?(brand:, notification_type:)
      contract = D8n::Platform::BrandRegistry.fetch(brand:)
      contract.notifications.notification_types.include?(notification_type)
    rescue D8n::Platform::BrandRegistry::UnsupportedBrand
      false
    end
    private_class_method :allowed_for_brand?
  end
end
