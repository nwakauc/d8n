module Notifications
  module Types
    Definition = Data.define(:code, :title, :body, :email_subject, :allowed_payload_keys)

    # `actor`/`target` (shared by every D8N dating event below): opaque public
    # identifiers only — { actor: { profile_id: }, target: { type:, id: } }. A
    # message target also carries an opaque `message_id` so delivery can resolve
    # the exact message under current authorization without persisting content. No
    # name, photo, bio, or message body is ever embedded here; the frontend
    # resolves `actor`/`target` through the normal owner-scoped endpoints
    # (profile detail, match, conversation), which already enforce block/
    # suspension/closure access on their own. That keeps a notification safe to
    # retain even after the actor is later blocked or becomes unavailable — there
    # is nothing sensitive in the row to leak, only an id that may fail to resolve.
    DATING_EVENT_PAYLOAD_KEYS = %w[actor target].freeze

    DEFINITIONS = {
      "dateza.welcome" => Definition.new(
        code: "dateza.welcome",
        title: "Welcome to DateZA",
        body: "Your account is ready. Complete your profile and start meeting people worth meeting.",
        email_subject: "Welcome to DateZA",
        allowed_payload_keys: []
      ),
      "dateza.like_received" => Definition.new(
        code: "dateza.like_received",
        title: "Someone likes you",
        body: "You have a new like on DateZA. Open the app to see who.",
        email_subject: "Someone likes you on DateZA",
        allowed_payload_keys: DATING_EVENT_PAYLOAD_KEYS
      ),
      "dateza.match_created" => Definition.new(
        code: "dateza.match_created",
        title: "It's a match!",
        body: "You have a new match on DateZA. Say hello.",
        email_subject: "You have a new match on DateZA",
        allowed_payload_keys: DATING_EVENT_PAYLOAD_KEYS
      ),
      "dateza.opener_received" => Definition.new(
        code: "dateza.opener_received",
        title: "You received an opener",
        body: "Someone sent you an opener on DateZA. Open the app to read it.",
        email_subject: "You received an opener on DateZA",
        allowed_payload_keys: DATING_EVENT_PAYLOAD_KEYS
      ),
      "dateza.message_received" => Definition.new(
        code: "dateza.message_received",
        title: "New message",
        body: "You have a new message on DateZA.",
        email_subject: "New message on DateZA",
        allowed_payload_keys: DATING_EVENT_PAYLOAD_KEYS
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
