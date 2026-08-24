module Hooks
  # Creates a 🔥 Hook: the sender's single unsolicited opener to a recipient.
  # Mirrors Matching::LikeProfile's shape (viewer discoverable, target resolved by
  # public id, both rows locked, target re-checked through EligibilityScope) so a
  # Hook can never reach anyone a Like couldn't — blocked, suspended, closed,
  # hidden, cross-brand, or ineligible targets all fail closed as
  # `profile_unavailable`.
  #
  # The opener is stored on the Hook itself; NO Match/Conversation/Message is
  # created yet. That is what makes the "one message until they reply" lock
  # enforceable at the data layer: with no conversation there is no message
  # endpoint to reach, and the unique (sender, recipient) index makes a second
  # Hook impossible (concurrently too, via the RecordNotUnique rescue).
  class SendHook
    Result = Data.define(:hook)

    def self.call(user:, brand:, target_public_id:, message:, eligibility_policy: nil)
      new(user:, brand:, target_public_id:, message:, eligibility_policy:).call
    end

    def initialize(user:, brand:, target_public_id:, message:, eligibility_policy:)
      @user = user
      @brand = brand
      @target_public_id = target_public_id
      @raw_message = message
      @eligibility_policy = eligibility_policy
    end

    def call
      viewer = Matching::ProfileParticipant.discoverable!(user:, brand:)
      target = brand.profiles.kept.find_by(public_id: target_public_id)
      raise Matching::InteractionError, :profile_unavailable if target.blank? || target.id == viewer.id

      # Validate the opener before opening a transaction — a blank/oversized body
      # is the caller's error, not a reason to hold row locks.
      message = Messaging::MessageBody.prepare(raw_message)

      result = nil
      Profile.transaction do
        lock_participants!(viewer:, target:)
        Matching::ProfileParticipant.discoverable!(user: user.reload, brand:)
        ensure_target_eligible!(viewer:, target:)
        enforce_rate_limit!(viewer:)
        guard_relationship!(viewer:, target:)
        # A prior pass by the sender is superseded by the stronger Hook intent.
        ProfilePass.kept.find_by(brand:, passer_profile: viewer, passed_profile: target)&.update!(deleted_at: Time.current)

        hook = Hook.create!(
          brand:, sender_profile: viewer, recipient_profile: target,
          message:, expires_at: Policy::EXPIRES_IN.from_now
        )
        record_event(brand:, user:, viewer:, target:, hook:)
        result = Result.new(hook:)
      end
      result
    rescue ActiveRecord::RecordNotUnique
      # Lost a race (or a resend attempt): one Hook per pair, ever.
      raise Matching::InteractionError, :already_hooked
    end

    private

    attr_reader :user, :brand, :target_public_id, :raw_message, :eligibility_policy

    def lock_participants!(viewer:, target:)
      locked_ids = Profile.kept.where(brand:, id: [ viewer.id, target.id ]).order(:id).lock.pluck(:id)
      raise Matching::InteractionError, :profile_unavailable unless locked_ids.size == 2
    end

    def ensure_target_eligible!(viewer:, target:)
      policy = eligibility_policy || Matching::StrategyRegistry.eligibility_policy_for(brand:)
      eligible = Matching::EligibilityScope.call(
        brand:, viewer:, policy:
      ).where(id: target.id).exists?
      raise Matching::InteractionError, :profile_unavailable unless eligible
    end

    def enforce_rate_limit!(viewer:)
      window_start = Policy::RATE_WINDOW.ago
      recent = Hook.kept.where(brand:, sender_profile: viewer).where(created_at: window_start..).order(:created_at)
      return if recent.count < Policy.daily_limit_for(viewer)

      retry_after = (recent.first.created_at + Policy::RATE_WINDOW - Time.current).ceil
      raise Matching::InteractionError.new(:hook_rate_limited, retry_after: [ retry_after, 1 ].max)
    end

    def guard_relationship!(viewer:, target:)
      profile_a_id, profile_b_id = Match.canonical_pair(viewer.id, target.id)
      if Match.kept.status_active.exists?(brand:, profile_a_id:, profile_b_id:)
        raise Matching::InteractionError, :already_matched
      end
      if Like.kept.exists?(brand:, liker_profile: viewer, liked_profile: target)
        raise Matching::InteractionError, :already_liked
      end
      # They already Hooked the viewer: the viewer should reply from their inbox,
      # not open a competing Hook. Safe to reveal — the viewer is the recipient
      # and already sees it there.
      if Hook.live.exists?(brand:, sender_profile: target, recipient_profile: viewer)
        raise Matching::InteractionError, :incoming_hook
      end
    end

    def record_event(brand:, user:, viewer:, target:, hook:)
      SecurityEvent.create!(
        brand:, user:,
        event_type: "hooks.sent",
        severity: :info,
        metadata: { hook_id: hook.id, sender_profile_id: viewer.id, recipient_profile_id: target.id }
      )
    end
  end
end
