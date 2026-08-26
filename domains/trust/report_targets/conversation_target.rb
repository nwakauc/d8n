module Trust
  module ReportTargets
    # The conversation as a whole, for pattern-level harm that no single message
    # captures (repeated harassment, a scam pattern, escalating coercion). Origin
    # does not matter: a Match-origin conversation and an accepted-Hook-origin
    # conversation (Hooks::ReplyToHook) are both plain Conversation records once
    # created, so authorization is identical either way.
    #
    # Authorization mirrors MessageTarget exactly, and for the same reason: the
    # viewer must be a kept ConversationParticipant of THIS conversation. This is
    # deliberately not MatchAccess, so the report path survives a block,
    # suspension, or closure of the other participant. The responsible profile is
    # the other participant.
    #
    # Evidence is a BOUNDED snapshot — the most recent CONTEXT_WINDOW kept
    # messages that existed at report time — so a moderator can triage a pattern
    # without the report becoming a copy of the whole conversation. This is
    # deliberately different from MessageTarget, whose evidence is the single
    # reported message and nothing else (see ADR 0018): a message report is about
    # one piece of content, a conversation report is about a pattern, and the
    # bounded window is where that pattern-level context belongs.
    class ConversationTarget
      CONTEXT_WINDOW = 20

      def self.resolve(brand:, viewer:, target_public_id:)
        conversation = Conversation.kept.where(brand:).find_by(public_id: target_public_id)
        raise AccessError, :target_unavailable if conversation.blank?

        participant = ConversationParticipant.kept.exists?(
          brand:, conversation_id: conversation.id, profile_id: viewer.id
        )
        raise AccessError, :target_unavailable unless participant

        other = conversation.other_profile(viewer)
        raise AccessError, :target_unavailable if other.blank?

        Resolution.new(
          target_type: "conversation",
          target_id: conversation.id,
          reported_profile: other,
          evidence: {
            "conversation_public_id" => conversation.public_id,
            "other_profile_id" => other.id,
            "messages" => bounded_context(conversation)
          }
        )
      end

      def self.bounded_context(conversation)
        conversation.messages.kept.order(created_at: :desc).limit(CONTEXT_WINDOW).to_a.reverse.map do |message|
          {
            "message_public_id" => message.public_id,
            "sender_profile_id" => message.sender_profile_id,
            "body" => message.body,
            "content_created_at" => message.created_at.iso8601
          }
        end
      end
      private_class_method :bounded_context
    end
  end
end
