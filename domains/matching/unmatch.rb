module Matching
  # Ends an active Match at either participant's request — distinct from
  # Trust::BlockProfile, which also ends the Match but additionally creates a
  # ProfileBlock and is the stronger safety action. Unmatch never touches
  # ProfileBlock; the two are independent terminal outcomes for the same
  # relationship-state machine.
  #
  # Reuses the same canonical-order profile locking Trust::BlockProfile and
  # Matching::LikeProfile already use, so concurrent Unmatch/Block/Like calls on
  # the same pair serialize on the profile rows rather than deadlocking or
  # racing (see #lock_participants!).
  #
  # Idempotent: unmatching an already-ended Match (whether ended by a prior
  # Unmatch or by a Block) is a safe no-op — Result#already_ended distinguishes
  # the two outcomes for logging/tests, but the controller treats both as
  # success, matching how Trust::UnblockProfile's DELETE is unconditionally
  # idempotent.
  class Unmatch
    Result = Data.define(:match, :already_ended)

    def self.call(user:, brand:, match_public_id:)
      new(user:, brand:, match_public_id:).call
    end

    def initialize(user:, brand:, match_public_id:)
      @user = user
      @brand = brand
      @match_public_id = match_public_id
    end

    def call
      viewer = ProfileParticipant.match_member!(user:, brand:)
      match = Match.kept.where(brand:).find_by(public_id: match_public_id)
      raise InteractionError, :match_unavailable if match.blank? || !participant?(match:, viewer:)

      result = nil
      Profile.transaction do
        lock_participants!(match:)
        current = Match.kept.where(brand:).lock.find_by(id: match.id)
        raise InteractionError, :match_unavailable if current.blank?

        if current.status_ended?
          result = Result.new(match: current, already_ended: true)
          next
        end

        discard_likes!(match: current)
        current.update!(status: :ended)
        # Deliberately does NOT touch Conversation/Message rows. Messaging
        # access (send, read, and starting a new conversation) is already
        # fully gated on Match.status_active via Messaging::MatchAccess /
        # ConversationAccess, so ending the Match alone is sufficient to make
        # the conversation unreachable for new activity. Messaging::ConversationList
        # deliberately does NOT re-check match status — an existing, tested
        # behaviour (Api::V1::ConversationsControllerTest#"retains read-only
        # conversation metadata after a match ends") keeps the conversation's
        # card visible (with its last-message preview) after the match ends,
        # so a member can still see who they used to talk to. Closing the
        # Conversation record here would silently break that intentional,
        # already-shipped behaviour for the exact same reason Block doesn't
        # do it either.
        result = Result.new(match: current, already_ended: false)
      end
      result
    end

    private

    attr_reader :user, :brand, :match_public_id

    def participant?(match:, viewer:)
      [ match.profile_a_id, match.profile_b_id ].include?(viewer.id)
    end

    def lock_participants!(match:)
      ids = [ match.profile_a_id, match.profile_b_id ]
      locked_ids = Profile.kept.where(brand:, id: ids).order(:id).lock.pluck(:id)
      raise InteractionError, :match_unavailable unless locked_ids.size == 2
    end

    def discard_likes!(match:)
      now = Time.current
      Like.kept.where(brand:).where(
        liker_profile_id: [ match.profile_a_id, match.profile_b_id ],
        liked_profile_id: [ match.profile_a_id, match.profile_b_id ]
      ).update_all(deleted_at: now, updated_at: now)
    end
  end
end
