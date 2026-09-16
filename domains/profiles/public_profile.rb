module Profiles
  # Retrieves another member's safe public profile for direct (deep-link) access
  # from a stable public profile UUID — the authoritative source behind a
  # refreshable /profiles/:id route.
  #
  # It enforces the SAME fundamental visibility/safety rules as discovery
  # (Matching::VisibilityScope): brand isolation, active/visible lifecycle
  # (excluding suspended/closed/discarded/inactive accounts), minimum age, and
  # blocks in either direction. It deliberately does NOT reapply discovery's
  # reciprocal gender/age/distance ranking, so a profile a member could reach
  # from discovery keeps resolving directly even after ranking or dating
  # preferences change (a changed preference must not break a valid profile link).
  #
  # Every unavailable case — unknown id, wrong brand, hidden, inactive,
  # suspended, closed, discarded, or blocked in either direction — is
  # indistinguishable to the caller (Unavailable), never leaking why.
  class PublicProfile
    # The viewer is not an eligible member (e.g. no active discoverable profile).
    class ViewerIneligible < StandardError; end
    # The target is unavailable for any reason; deliberately undifferentiated.
    class Unavailable < StandardError; end

    def self.call(user:, brand:, public_id:)
      new(user:, brand:, public_id:).call
    end

    def initialize(user:, brand:, public_id:)
      @user = user
      @brand = brand
      @public_id = public_id
    end

    def call
      viewer = viewer_profile

      target = Matching::VisibilityScope.call(brand:, viewer:)
        .where(public_id:)
        .includes(
          :brand,
          { profile_photos: { display_image_attachment: :blob } },
          { profile_video: [ { playback_attachment: :blob }, { poster_attachment: :blob } ] },
          { profile_option_selections: [ :profile_option, :profile_option_group ] }
        )
        .first

      raise Unavailable if target.nil?

      target
    end

    private

    attr_reader :user, :brand, :public_id

    def viewer_profile
      Matching::ProfileParticipant.discoverable!(user:, brand:)
    rescue Matching::InteractionError
      raise ViewerIneligible
    end
  end
end
