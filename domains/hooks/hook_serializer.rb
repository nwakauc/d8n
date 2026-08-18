module Hooks
  # Recipient-facing shape for one received Hook (inbox item): the opener text, the
  # sender's SAFE public profile (via Profiles::PublicSerializer — no private
  # identifiers), and the expiry so the client can show a countdown. Only the
  # authorized recipient ever sees this; Hooks are private and never enumerable by
  # third parties.
  class HookSerializer
    def self.call(hook:)
      {
        id: hook.public_id,
        message: hook.message,
        created_at: hook.created_at.iso8601,
        expires_at: hook.expires_at.iso8601,
        sender: Profiles::PublicSerializer.call(profile: hook.sender_profile)
      }
    end

    # Minimal sender-facing acknowledgement returned when a Hook is created. The
    # sender learns only that their opener is pending and when it lapses — never
    # anything about what the recipient does with it.
    def self.sent(hook:)
      {
        id: hook.public_id,
        status: hook.status,
        created_at: hook.created_at.iso8601,
        expires_at: hook.expires_at.iso8601
      }
    end
  end
end
