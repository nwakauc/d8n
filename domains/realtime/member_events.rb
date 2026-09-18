module Realtime
  # Existing Action Cable adapter: PostgreSQL LISTEN/NOTIFY in production, with
  # one listener per process. Browser transport is SSE through the existing BFF.
  class MemberEvents
    def self.stream_name(brand_id:, user_id:)
      "member:#{brand_id}:#{user_id}"
    end

    def self.publish(brand_id:, user_id:, type:, **payload)
      ActionCable.server.broadcast(stream_name(brand_id:, user_id:), { type:, **payload })
    rescue StandardError
      # The durable database/outbox remains authoritative if ephemeral delivery
      # is unavailable. Reconnection/focus reconciles state; writes still succeed.
      Rails.logger.warn("member_realtime_publish_failed")
    end

    def self.message_created(message)
      message.conversation.conversation_participants.kept.each do |participant|
        publish(brand_id: message.brand_id, user_id: participant.user_id,
          type: "message_created", event_id: "message:#{message.public_id}",
          conversation_id: message.conversation.public_id, message_id: message.public_id,
          message: Messaging::MessageSerializer.call(message:),
          incoming: participant.profile_id != message.sender_profile_id,
          actor_profile_id: message.sender_profile.public_id, occurred_at: message.created_at.iso8601(6))
      end
    end

    def self.notification_changed(notification, created:)
      publish(brand_id: notification.brand_id, user_id: notification.user_id,
        type: created ? "notification_created" : "read_state_changed",
        event_id: "notification:#{notification.public_id}", notification_id: notification.public_id, notification: Notifications::Presenter.call(notification), occurred_at: notification.notification_event.occurred_at.iso8601(6))
    end

    def self.authorized_payload?(payload:, session_id:, brand_id:, user_id:)
      event = JSON.parse(payload)
      return true unless event["type"] == "message_created"

      session = Session.find(session_id)
      Identity::InteractionAccess.authorize!(session:, brand: session.brand, surface: :history)
      Messaging::ConversationAccess.find!(user: session.user, brand: session.brand,
        conversation_public_id: event["conversation_id"], allow_ended: true)
      true
    rescue Messaging::AccessError, Identity::InteractionAccess::IdentifierVerificationRequired, JSON::ParserError
      false
    end

    def self.session_active?(session_id:, brand_id:, user_id:)
      session = Session.active.includes(:user, :credential, :brand).find_by(id: session_id, brand_id:, user_id:)
      session && session.user.active? && session.user.deleted_at.nil? &&
        session.brand.active? && session.brand.deleted_at.nil? &&
        (session.credential.nil? || (session.credential.active? && session.credential.deleted_at.nil?)) &&
        BrandMembership.kept.active.exists?(brand_id:, user_id:)
    end
  end
end
