module Messaging
  class StartConversation
    Result = Data.define(:conversation, :viewer, :created)

    def self.call(user:, brand:, match_public_id:)
      access = MatchAccess.find!(user:, brand:, match_public_id:)
      result = nil
      Profile.transaction do
        lock_profiles!(brand:, match: access.match)
        access.match.lock!
        access = MatchAccess.find!(user:, brand:, match_public_id:)
        conversation = Conversation.find_or_initialize_by(match: access.match)
        created = conversation.new_record?
        if conversation.new_record?
          conversation.brand = brand
          conversation.save!
          [ access.match.profile_a, access.match.profile_b ].each do |profile|
            conversation.conversation_participants.create!(profile:, user: profile.user, brand:)
          end
        end
        result = Result.new(conversation:, viewer: access.viewer, created:)
      end
      result
    end

    def self.lock_profiles!(brand:, match:)
      ids = [ match.profile_a_id, match.profile_b_id ]
      locked_ids = Profile.kept.where(brand:, id: ids).order(:id).lock.pluck(:id)
      raise AccessError, :conversation_unavailable unless locked_ids.size == 2
    end
    private_class_method :lock_profiles!
  end
end
