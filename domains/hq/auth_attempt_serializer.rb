module Hq
  # Moderator-facing AuthAttempt representation. No credential/session data --
  # only what's needed to investigate suspicious authentication activity.
  class AuthAttemptSerializer
    def self.call(attempt:)
      {
        id: attempt.id,
        kind: attempt.kind,
        result: attempt.result,
        identifier: attempt.identifier,
        ip_address: attempt.ip_address,
        created_at: attempt.created_at.iso8601
      }
    end
  end
end
