module Messaging
  class MatchAccess
    Result = Data.define(:match, :viewer)

    def self.find!(user:, brand:, match_public_id:)
      viewer = Matching::ProfileParticipant.match_member!(user:, brand:)
      match = Match.kept.status_active.includes(
        profile_a: [ :user, :brand_membership ],
        profile_b: [ :user, :brand_membership ]
      ).find_by(brand:, public_id: match_public_id)

      available = match && [ match.profile_a_id, match.profile_b_id ].include?(viewer.id) &&
        profile_available?(match.profile_a) && profile_available?(match.profile_b) &&
        !Trust::BlockPolicy.blocked_between?(brand:, first: match.profile_a, second: match.profile_b)
      raise AccessError, :conversation_unavailable unless available

      Result.new(match:, viewer:)
    rescue Matching::InteractionError
      raise AccessError, :conversation_unavailable
    end

    # Public: a reusable "this profile may participate in messaging right now"
    # predicate (kept, unsuspended, active user + active membership). Also used by
    # Hooks::ReplyToHook when it promotes an accepted Hook into a conversation.
    def self.profile_available?(profile)
      profile.deleted_at.nil? && !profile.suspended? &&
        profile.user.deleted_at.nil? && profile.user.active? &&
        profile.brand_membership.deleted_at.nil? && profile.brand_membership.active?
    end
  end
end
