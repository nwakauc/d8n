module D8n
  module Platform
    module Capabilities
      module Notify
        DEFINITIONS = [
          CapabilityDefinition.new(key: "notify.event", status: :available,
            implementations: %w[Notifications::EventPublisher Notifications::MaterializeEvent]),
          CapabilityDefinition.new(key: "notify.inbox", status: :available,
            implementations: %w[Notifications::Inbox Notifications::Presenter]),
          CapabilityDefinition.new(key: "notify.email", status: :available,
            implementations: %w[Notifications::Email Notifications::EmailSender]),
          CapabilityDefinition.new(key: "notify.sms", status: :available,
            implementations: %w[Notifications::Sms Notifications::SmsSender]),
          CapabilityDefinition.new(key: "notify.push", status: :available,
            implementations: %w[Notifications::Push Notifications::DeliverProductNotificationJob])
        ].freeze

        def self.definitions = DEFINITIONS
      end
    end
  end
end
