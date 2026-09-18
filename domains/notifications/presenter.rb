module Notifications
  class Presenter
    def self.call(notification)
      definition = Types.fetch(notification.notification_type)
      title = definition.title
      body = definition.body
      if notification.notification_type == "date9ja.profile_viewed"
        actor = Profile.kept.find_by(brand: notification.brand, public_id: notification.payload.dig("actor", "profile_id"))
        recipient = Profile.kept.find_by(brand: notification.brand, user: notification.user, brand_membership: notification.brand_membership)
        if actor && recipient && Messaging::MatchAccess.profile_available?(actor) &&
            Messaging::MatchAccess.profile_available?(recipient) &&
            !Trust::BlockPolicy.blocked_between?(brand: notification.brand, first: recipient, second: actor)
          name = actor.display_name.to_s.squish.truncate(80, omission: "").presence || "Someone"
          title = "#{name} viewed your profile"
        end
      end
      {
        id: notification.public_id,
        type: notification.notification_type,
        title:,
        body:,
        payload: notification.payload,
        read_at: notification.read_at&.iso8601,
        created_at: notification.created_at.iso8601
      }
    end
  end
end
