module Trust
  module ReportTargets
    # A specific chat message. Authorization is deliberately NOT MatchAccess:
    # reporting must survive a block/suspension/closure of the sender (§18/§19), so
    # the only gate is "the viewer is a participant of this message's conversation".
    # That is true for exactly the two people in the match and can never be forged
    # by enumerating message ids. The responsible profile is the sender, derived
    # from the message. A viewer cannot report their own message.
    #
    # Evidence: an immutable snapshot of the reported message (sender, conversation,
    # type, body, timestamp) so moderation still knows what was flagged if the
    # message is later unsent/deleted. No surrounding conversation history is
    # copied. This body snapshot lives only on the report row (moderator-only),
    # never in logs or SecurityEvent metadata (see ADR 0018).
    #
    # Chat media (D8N Chat Media): a snapshot of each attachment's METADATA
    # (public id, media kind, position, dimensions/duration, processing state)
    # is included too, deliberately never a signed URL or storage key — the
    # same "evidence must not depend on a live media URL" principle
    # Trust::ReportTargets::MediaTarget already documents for profile photos.
    # If the sender later deletes the attachment (Messaging::DeleteAttachment
    # purges the R2 object), this metadata still identifies exactly what was
    # reported even though the pixels are gone — the same accepted beta
    # retention limitation as MediaTarget, pending a ModerationHold seam.
    class MessageTarget
      def self.resolve(brand:, viewer:, target_public_id:)
        message = Message.kept.where(brand:).find_by(public_id: target_public_id)
        raise AccessError, :target_unavailable if message.blank?

        participant = ConversationParticipant.kept.exists?(
          brand:, conversation_id: message.conversation_id, profile_id: viewer.id
        )
        sender = message.sender_profile
        raise AccessError, :target_unavailable unless participant && sender && sender.id != viewer.id

        Resolution.new(
          target_type: "message",
          target_id: message.id,
          reported_profile: sender,
          evidence: {
            "message_public_id" => message.public_id,
            "conversation_public_id" => message.conversation.public_id,
            "sender_profile_id" => sender.id,
            "message_type" => message.message_attachments.any? ? "media" : "text",
            "body" => message.body,
            "attachments" => attachment_evidence(message),
            "reply_to" => message.reply_to_message_id.present? ? message.reply_snapshot : nil,
            "content_created_at" => message.created_at.iso8601
          }
        )
      end

      def self.attachment_evidence(message)
        message.message_attachments.map do |attachment|
          {
            "attachment_public_id" => attachment.public_id,
            "media_kind" => attachment.media_kind,
            "position" => attachment.position,
            "processing_state" => attachment.processing_state,
            "deleted" => !attachment.kept?,
            "width" => attachment.width,
            "height" => attachment.height,
            "duration_seconds" => attachment.duration_seconds&.to_f
          }
        end
      end
      private_class_method :attachment_evidence
    end
  end
end
