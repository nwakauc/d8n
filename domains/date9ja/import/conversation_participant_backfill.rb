module Date9ja
  module Import
    # One-time repair for conversations imported by an earlier
    # HistoricalGraphImport version that predates participant-row creation
    # (fixed going forward in HistoricalGraphImport#ensure_conversation_participants!).
    # Reads only already-imported D8N data -- no legacy snapshot connection.
    class ConversationParticipantBackfill
      Result = Data.define(:conversations_checked, :participants_created)

      def self.call(brand:)
        new(brand:).call
      end

      def initialize(brand:)
        @brand = brand
      end

      def call
        checked = created = 0
        Conversation.kept.where(brand:).includes(:match).find_each do |conversation|
          checked += 1
          match = conversation.match
          next if match.blank?

          existing = conversation.conversation_participants.pluck(:profile_id).to_set
          [ match.profile_a, match.profile_b ].each do |profile|
            next if profile.blank? || existing.include?(profile.id)

            conversation.conversation_participants.create!(
              profile:, user: profile.user, brand:,
              created_at: conversation.created_at, updated_at: conversation.updated_at
            )
            created += 1
          end
        end
        Result.new(conversations_checked: checked, participants_created: created)
      end

      private

      attr_reader :brand
    end
  end
end
