module Hooks
  # The recipient explicitly declines a pending Hook. Terminal and private: the
  # sender is never told a decline happened (their viewer-relative state collapses
  # to `unavailable`, the same bucket as expiry or a block, so a decline is
  # indistinguishable from being ignored-then-expired). A non-live Hook (already
  # accepted/declined/expired, or not the viewer's) fails closed as the neutral
  # `hook_unavailable`.
  class DeclineHook
    Result = Data.define(:hook)

    def self.call(user:, brand:, hook_public_id:)
      new(user:, brand:, hook_public_id:).call
    end

    def initialize(user:, brand:, hook_public_id:)
      @user = user
      @brand = brand
      @hook_public_id = hook_public_id
    end

    def call
      viewer = Matching::ProfileParticipant.match_member!(user:, brand:)
      result = nil
      Profile.transaction do
        hook = Hook.kept.lock.find_by(brand:, public_id: hook_public_id, recipient_profile: viewer)
        raise Messaging::AccessError, :hook_unavailable unless hook&.live?

        hook.update!(status: :declined, declined_at: Time.current)
        record_event(brand:, user:, hook:)
        result = Result.new(hook:)
      end
      result
    rescue Matching::InteractionError
      raise Messaging::AccessError, :hook_unavailable
    end

    private

    attr_reader :user, :brand, :hook_public_id

    def record_event(brand:, user:, hook:)
      SecurityEvent.create!(
        brand:, user:,
        event_type: "hooks.declined",
        severity: :info,
        metadata: { hook_id: hook.id, sender_profile_id: hook.sender_profile_id, recipient_profile_id: hook.recipient_profile_id }
      )
    end
  end
end
