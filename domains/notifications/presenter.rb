module Notifications
  class Presenter
    def self.call(notification)
      definition = Types.fetch(notification.notification_type)
      {
        id: notification.public_id,
        type: notification.notification_type,
        title: definition.title,
        body: definition.body,
        payload: notification.payload,
        read_at: notification.read_at&.iso8601,
        created_at: notification.created_at.iso8601
      }
    end
  end
end
