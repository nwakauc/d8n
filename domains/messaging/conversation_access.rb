module Messaging
  # Resolves and authorizes an active conversation for the current member by its
  # public id, reusing MatchAccess as the single source of truth for every
  # message read/write. MatchAccess rechecks: the viewer is a current-brand match
  # member, the match is active, both profiles/users/memberships are available and
  # unsuspended, and neither side blocks the other. Unknown, cross-brand,
  # non-participant, ended, unavailable, and blocked conversations all fail with
  # the same neutral `conversation_unavailable` so nothing is enumerable and no
  # block is ever disclosed.
  class ConversationAccess
    Result = Data.define(:conversation, :match, :viewer)

    def self.find!(user:, brand:, conversation_public_id:)
      conversation = Conversation.kept.status_active.find_by(brand:, public_id: conversation_public_id)
      raise AccessError, :conversation_unavailable if conversation.blank?

      access = MatchAccess.find!(user:, brand:, match_public_id: conversation.match.public_id)
      Result.new(conversation:, match: access.match, viewer: access.viewer)
    end
  end
end
