module Trust
  # Lists the profiles the current member has blocked, newest first, for the
  # Settings / Safety "Blocked users" surface. Only outgoing (blocker == viewer)
  # blocks are returned — an incoming block is invisible to the blocked user by
  # design. Blocked profiles whose account was since removed are excluded so the
  # frontend never shows an entry that can no longer be unblocked.
  class ListBlockedProfiles
    def self.call(user:, brand:)
      viewer = Matching::ProfileParticipant.match_member!(user:, brand:)

      ProfileBlock.kept
        .where(brand:, blocker_profile: viewer)
        .joins(:blocked_profile).merge(Profile.kept)
        .includes(:blocked_profile)
        .order(created_at: :desc)
    end
  end
end
