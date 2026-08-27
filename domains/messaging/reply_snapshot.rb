module Messaging
  # Frozen-at-send-time preview of the message being replied to. Deliberately
  # mirrors Trust::ReportTargets::MessageTarget's evidence snapshot: safe,
  # non-live metadata only (no signed URL, no storage key, no full body echo
  # is required to keep working), so a reply preview keeps rendering exactly
  # what it looked like when the reply was sent even if the original message
  # or one of its attachments is later deleted — MessageSerializer never needs
  # to re-touch the original row to show the preview.
  class ReplySnapshot
    BODY_EXCERPT_LENGTH = 280

    def self.build(message)
      {
        "message_public_id" => message.public_id,
        "sender_profile_id" => message.sender_profile.public_id,
        "message_type" => message.message_attachments.any? ? "media" : "text",
        "body_excerpt" => message.body&.truncate(BODY_EXCERPT_LENGTH)
      }
    end
  end
end
