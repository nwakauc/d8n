module Notifications
  module EmailPresenters
    class Date9ja
      def self.call(notification:)
        new(notification:).call
      end

      def initialize(notification:)
        @notification = notification
      end

      def call
        actor = eligible_actor
        return fallback unless actor

        name = actor.display_name.to_s.squish.truncate(80, omission: "").presence || "Someone"
        result(
          subject: "#{name} viewed your Date9ja profile",
          title: "#{name} viewed your Date9ja profile",
          body: "#{name} took a closer look at your profile.",
          preheader: "#{name} took a closer look at your profile.",
          actor_name: name,
          actor_image_url: actor_image_url(actor),
          cta_label: "View their profile",
          cta_url: DeepLink.for(brand:, path: "member/p/#{notification.payload.dig('actor', 'profile_id')}")
        )
      end

      private

      attr_reader :notification

      def eligible_actor
        recipient = Profile.kept.find_by(brand:, user: notification.user, brand_membership: notification.brand_membership)
        actor = Profile.kept.find_by(brand:, public_id: notification.payload.dig("actor", "profile_id"))
        return unless recipient && actor
        return unless Messaging::MatchAccess.profile_available?(recipient) && Messaging::MatchAccess.profile_available?(actor)
        return if Trust::BlockPolicy.blocked_between?(brand:, first: recipient, second: actor)
        actor
      end

      def actor_image_url(actor)
        photo = actor.profile_photos.deliverable.ordered.with_attached_display_image.first
        photo&.display_image&.url(expires_in: Profiles::PhotoUpload::RETRIEVAL_URL_EXPIRES_IN)
      end

      def brand
        notification.brand
      end

      def fallback
        definition = Types.fetch(notification.notification_type)
        result(subject: definition.email_subject, title: definition.title, body: definition.body, preheader: definition.body,
          cta_label: "Open Date9ja", cta_url: DeepLink.for(brand:, path: ""))
      end

      def result(**attributes)
        EmailPresentation::Result.new(
          subject: attributes[:subject], title: attributes[:title], body: attributes[:body],
          preheader: attributes[:preheader], actor_name: attributes[:actor_name],
          actor_image_url: attributes[:actor_image_url], preview: attributes[:preview],
          cta_label: attributes[:cta_label], cta_url: attributes[:cta_url]
        )
      end
    end
  end
end
