module Messaging
  class StartConversation
    Result = Data.define(:conversation, :viewer, :created)

    def self.call(user:, brand:, match_public_id:)
      access = MatchAccess.find!(user:, brand:, match_public_id:)
      conversation = nil
      created = false

      access.match.with_lock do
        access = MatchAccess.find!(user:, brand:, match_public_id:)
        conversation = Conversation.find_or_initialize_by(match: access.match)
        if conversation.new_record?
          conversation.brand = brand
          conversation.save!
          [ access.match.profile_a, access.match.profile_b ].each do |profile|
            conversation.conversation_participants.create!(profile:, user: profile.user, brand:)
          end
          created = true
        end
      end

      Result.new(conversation:, viewer: access.viewer, created:)
    end
  end
end
