module Notifications
  module EmailPresenters
    class Dateza
      PREVIEW_LENGTH = 100

      def self.call(notification:)
        new(notification:).call
      end

      def initialize(notification:)
        @notification = notification
      end

      def call
        return welcome if notification.notification_type == "dateza.welcome"

        actor = eligible_actor
        return privacy_fallback unless actor

        case notification.notification_type
        when "dateza.message_received" then message_received(actor)
        when "dateza.match_created" then dating_event(actor, "It's a match!", "You and #{actor_name(actor)} matched on DateZA.", "Say hello", target_path)
        when "dateza.opener_received" then dating_event(actor, "#{actor_name(actor)} sent you an opener", "They've made the first move. See what they said and reply when you're ready.", "Read opener", target_path)
        when "dateza.like_received" then dating_event(actor, "Someone likes you", "A DateZA member is interested in you. Open DateZA to see who.", "See who likes you", target_path, expose_actor: false)
        else privacy_fallback
        end
      end

      private

      attr_reader :notification

      def welcome
        definition = Types.fetch(notification.notification_type)
        result(
          subject: definition.email_subject,
          title: definition.title,
          body: definition.body,
          preheader: "Your DateZA account is ready.",
          cta_label: "Complete your profile",
          cta_url: DeepLink.for(brand:, path: "profile")
        )
      end

      def message_received(actor)
        message = eligible_message(actor)
        return privacy_fallback unless message

        copy = message_copy(message, actor)
        result(
          subject: "#{actor_name(actor)} sent you a message on DateZA",
          title: "A message from #{actor_name(actor)}",
          body: copy,
          preheader: copy,
          actor_name: actor_name(actor),
          actor_image_url: actor_image_url(actor),
          preview: text_preview(message),
          cta_label: "Reply to #{actor_name(actor)}",
          cta_url: DeepLink.for(brand:, path: target_path)
        )
      end

      def dating_event(actor, title, body, cta_label, path, expose_actor: true)
        result(
          subject: title.include?(actor_name(actor)) ? "#{title} on DateZA" : "#{title} on DateZA",
          title:,
          body:,
          preheader: body,
          actor_name: expose_actor ? actor_name(actor) : nil,
          actor_image_url: expose_actor ? actor_image_url(actor) : nil,
          cta_label:,
          cta_url: DeepLink.for(brand:, path:)
        )
      end

      def privacy_fallback
        definition = Types.fetch(notification.notification_type)
        result(
          subject: definition.email_subject,
          title: definition.title,
          body: definition.body,
          preheader: definition.body,
          cta_label: "Open DateZA",
          cta_url: DeepLink.for(brand:, path: "")
        )
      end

      def eligible_actor
        recipient = Profile.kept.find_by(
          brand:, user: notification.user, brand_membership: notification.brand_membership
        )
        actor = Profile.kept.find_by(brand:, public_id: notification.payload.dig("actor", "profile_id"))
        return unless recipient && actor
        return unless Messaging::MatchAccess.profile_available?(recipient) && Messaging::MatchAccess.profile_available?(actor)
        return if Trust::BlockPolicy.blocked_between?(brand:, first: recipient, second: actor)
        return unless underlying_event_available?(recipient:, actor:)

        actor
      end

      def underlying_event_available?(recipient:, actor:)
        case notification.notification_type
        when "dateza.message_received"
          Messaging::ConversationAccess.find!(
            user: notification.user, brand:, conversation_public_id: notification.payload.dig("target", "id")
          )
          true
        when "dateza.match_created"
          access = Messaging::MatchAccess.find!(
            user: notification.user, brand:, match_public_id: notification.payload.dig("target", "id")
          )
          access.match.other_profile(recipient) == actor
        when "dateza.opener_received"
          Hook.live.exists?(brand:, public_id: notification.payload.dig("target", "id"), sender_profile: actor, recipient_profile: recipient)
        when "dateza.like_received"
          Like.kept.kind_like.exists?(brand:, liker_profile: actor, liked_profile: recipient)
        else
          false
        end
      rescue Messaging::AccessError
        false
      end

      def eligible_message(actor)
        message = Message.kept.includes(:message_attachments).find_by(
          brand:,
          public_id: notification.payload.dig("target", "message_id"),
          conversation: Conversation.kept.find_by(brand:, public_id: notification.payload.dig("target", "id")),
          sender_profile: actor
        )
        message if message&.kept?
      end

      def message_copy(message, actor)
        return text_preview(message) if message.body.present?

        kinds = message.message_attachments.select(&:kept?).map(&:media_kind)
        noun = if kinds.one? && kinds.first == "image"
          "a photo"
        elsif kinds.one? && kinds.first == "video"
          "a video"
        elsif kinds.present? && kinds.all?("image")
          "photos"
        elsif kinds.present? && kinds.all?("video")
          "videos"
        else
          "media"
        end
        "#{actor_name(actor)} sent you #{noun}."
      end

      def text_preview(message)
        return if message.body.blank?

        message.body.squish.truncate(PREVIEW_LENGTH, omission: "…")
      end

      def actor_name(actor)
        actor.display_name.to_s.squish.truncate(80, omission: "").presence || "Someone"
      end

      def actor_image_url(actor)
        photo = actor.profile_photos.deliverable.ordered.with_attached_display_image.first
        photo&.display_image&.url(expires_in: Profiles::PhotoUpload::RETRIEVAL_URL_EXPIRES_IN)
      end

      def target_path
        target = notification.payload.fetch("target")
        case target.fetch("type")
        when "conversation" then "conversations/#{target.fetch("id")}" 
        when "match" then "matches/#{target.fetch("id")}" 
        when "opener" then "openers/#{target.fetch("id")}" 
        when "profile" then "profiles/#{target.fetch("id")}" 
        else ""
        end
      end

      def brand
        notification.brand
      end

      def result(**attributes)
        EmailPresentation::Result.new(
          subject: attributes[:subject],
          title: attributes[:title],
          body: attributes[:body],
          preheader: attributes[:preheader],
          actor_name: attributes[:actor_name],
          actor_image_url: attributes[:actor_image_url],
          preview: attributes[:preview],
          cta_label: attributes[:cta_label],
          cta_url: attributes[:cta_url]
        )
      end
    end
  end
end
