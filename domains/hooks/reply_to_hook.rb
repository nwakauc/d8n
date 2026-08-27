module Hooks
  # The recipient's first reply to a pending Hook. There is no separate "accept"
  # step: replying IS acceptance. In one transaction, under a row lock on the Hook,
  # this atomically:
  #   1. verifies the Hook is still live (pending + unexpired) and both parties are
  #      available and not blocked either way,
  #   2. creates the canonical Match (active) and its Conversation + participants,
  #   3. materializes the sender's stored opener as the first Message and the
  #      recipient's text as the second,
  #   4. flips the Hook to accepted and links the Conversation.
  #
  # From here on the relationship is an ordinary Match + Conversation, so every
  # further message flows through the existing messaging endpoints — one chat
  # system, not two. The row lock guarantees two concurrent replies cannot both
  # unlock: the loser sees a non-live Hook and fails closed.
  class ReplyToHook
    Result = Data.define(:conversation, :message, :viewer, :hook)

    def self.call(user:, brand:, hook_public_id:, message:)
      new(user:, brand:, hook_public_id:, message:).call
    end

    def initialize(user:, brand:, hook_public_id:, message:)
      @user = user
      @brand = brand
      @hook_public_id = hook_public_id
      @raw_message = message
    end

    def call
      viewer = Matching::ProfileParticipant.match_member!(user:, brand:)
      body = Messaging::MessageBody.prepare(raw_message)

      result = nil
      Profile.transaction do
        hook = Hook.kept.lock.find_by(brand:, public_id: hook_public_id, recipient_profile: viewer)
        raise Messaging::AccessError, :hook_unavailable unless hook&.live?

        sender = hook.sender_profile
        lock_participants!(sender:, recipient: viewer)
        ensure_available!(sender:, recipient: viewer)

        conversation, created = ensure_conversation(brand:, sender:, recipient: viewer)
        # A reply always creates a brand-new Match: SendHook.guard_relationship!
        # refuses to let a Hook be sent while an active Match already exists
        # between the two profiles, so this can never resolve to a pre-existing
        # Match. That makes a separate "opener_replied" notification redundant
        # by construction — it would tell the sender the same thing match_created
        # already does ("they responded, you're now connected") for the exact
        # same transition, which is the same confusing-duplicate problem the
        # taxonomy avoids for Like -> Match. So only match_created is published
        # here; "opener_replied" is not a materialized notification type.
        Notifications::EventPublisher.match_created!(match: conversation.match)
        # Only stamp the opener when the conversation is brand new — a match that
        # somehow already existed keeps its own history intact.
        Message.create!(brand:, conversation:, sender_profile: sender, body: hook.message) if created
        reply = Message.create!(brand:, conversation:, sender_profile: viewer, body:)
        hook.update!(status: :accepted, accepted_at: Time.current, conversation:)
        record_event(brand:, user:, hook:, conversation:)

        result = Result.new(conversation:, message: reply, viewer:, hook:)
      end
      result
    rescue Matching::InteractionError
      raise Messaging::AccessError, :hook_unavailable
    end

    private

    attr_reader :user, :brand, :hook_public_id, :raw_message

    def lock_participants!(sender:, recipient:)
      locked_ids = Profile.kept.where(brand:, id: [ sender.id, recipient.id ]).order(:id).lock.pluck(:id)
      raise Messaging::AccessError, :hook_unavailable unless locked_ids.size == 2
    end

    def ensure_available!(sender:, recipient:)
      available = Messaging::MatchAccess.profile_available?(sender) &&
        Messaging::MatchAccess.profile_available?(recipient) &&
        !Trust::BlockPolicy.blocked_between?(brand:, first: sender, second: recipient)
      raise Messaging::AccessError, :hook_unavailable unless available
    end

    def ensure_conversation(brand:, sender:, recipient:)
      profile_a_id, profile_b_id = Match.canonical_pair(sender.id, recipient.id)
      match = Match.kept.status_active.find_or_create_by!(brand:, profile_a_id:, profile_b_id:)
      conversation = Conversation.find_or_initialize_by(match:)
      created = conversation.new_record?
      if created
        conversation.brand = brand
        conversation.save!
        [ match.profile_a, match.profile_b ].each do |profile|
          conversation.conversation_participants.create!(profile:, user: profile.user, brand:)
        end
      end
      [ conversation, created ]
    end

    def record_event(brand:, user:, hook:, conversation:)
      SecurityEvent.create!(
        brand:, user:,
        event_type: "hooks.accepted",
        severity: :info,
        metadata: {
          hook_id: hook.id,
          sender_profile_id: hook.sender_profile_id,
          recipient_profile_id: hook.recipient_profile_id,
          conversation_id: conversation.id
        }
      )
    end
  end
end
