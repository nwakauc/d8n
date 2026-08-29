module Notifications
  # D8N's shared dating-event taxonomy. Every method here is brand-agnostic —
  # callers in Matching/Hooks/Messaging never know or care whether a brand has
  # DateZA copy, HookUs copy, or no notification plan at all; Policy.handles?
  # (looked up from the recipient's own brand contract) decides that. A brand
  # with no plan for an event_type (HookUs today, for all five dating events)
  # makes every call below a safe no-op — no capability check, no branching,
  # needed at any call site.
  class EventPublisher
    def self.membership_registered!(membership:)
      publish!(
        event_type: "membership_registered",
        idempotency_key: "membership_registered:#{membership.id}",
        brand: membership.brand,
        user: membership.user,
        brand_membership: membership,
        payload: {}
      )
    end

    # A Like that does NOT immediately create a mutual Match. When it does,
    # Matching::LikeProfile calls match_created! instead — see that method's
    # comment for why the two are mutually exclusive for the same transition.
    def self.like_received!(like:, recipient:, actor:)
      publish!(
        event_type: "like_received",
        idempotency_key: "like_received:#{like.id}:#{recipient.id}",
        brand: recipient.brand,
        user: recipient.user,
        brand_membership: recipient.brand_membership,
        payload: { actor: { profile_id: actor.public_id }, target: { type: "profile", id: actor.public_id } }
      )
    end

    # Fired once per participant for an active Match, from whichever transition
    # created it (reciprocal Likes or an Opener reply — see Matching::LikeProfile
    # and Hooks::ReplyToHook). "One Match row = at most one match_created per
    # recipient" is enforced by the idempotency_key below, keyed on (match,
    # recipient) — safe to call unconditionally on every path that produces or
    # finds an active Match; retries and concurrent reciprocal actions can never
    # double-notify a participant.
    def self.match_created!(match:)
      [ match.profile_a, match.profile_b ].each do |recipient|
        actor = match.other_profile(recipient)
        publish!(
          event_type: "match_created",
          idempotency_key: "match_created:#{match.public_id}:#{recipient.id}",
          brand: recipient.brand,
          user: recipient.user,
          brand_membership: recipient.brand_membership,
          payload: { actor: { profile_id: actor.public_id }, target: { type: "match", id: match.public_id } }
        )
      end
    end

    def self.opener_received!(hook:)
      publish!(
        event_type: "opener_received",
        idempotency_key: "opener_received:#{hook.public_id}",
        brand: hook.recipient_profile.brand,
        user: hook.recipient_profile.user,
        brand_membership: hook.recipient_profile.brand_membership,
        payload: {
          actor: { profile_id: hook.sender_profile.public_id },
          target: { type: "opener", id: hook.public_id }
        }
      )
    end

    def self.message_received!(message:, recipient:)
      publish!(
        event_type: "message_received",
        idempotency_key: "message_received:#{message.public_id}:#{recipient.id}",
        brand: recipient.brand,
        user: recipient.user,
        brand_membership: recipient.brand_membership,
        payload: {
          actor: { profile_id: message.sender_profile.public_id },
          target: {
            type: "conversation",
            id: message.conversation.public_id,
            message_id: message.public_id
          }
        }
      )
    end

    # find_or_create_by! (not create_or_find_by!): NotificationEvent also has an
    # application-level `validates :idempotency_key, uniqueness: true`, which
    # runs a SELECT before any INSERT and raises RecordInvalid — not
    # RecordNotUnique — the instant a duplicate key is attempted. create_or_
    # find_by! only rescues RecordNotUnique, so it cannot recover from that
    # validation error and would raise on every retry. find_or_create_by! finds
    # the existing row first for the common sequential-retry case, and the
    # RecordNotUnique rescue below still covers a genuine concurrent race where
    # two callers pass the SELECT at the same instant.
    def self.publish!(event_type:, idempotency_key:, brand:, user:, brand_membership:, payload:)
      return unless Policy.handles?(brand:, event_type:)

      NotificationEvent.find_or_create_by!(idempotency_key:) do |event|
        event.brand = brand
        event.user = user
        event.brand_membership = brand_membership
        event.event_type = event_type
        event.payload = payload
        event.occurred_at = Time.current
      end
    rescue ActiveRecord::RecordNotUnique
      NotificationEvent.find_by!(idempotency_key:)
    end
    private_class_method :publish!
  end
end
