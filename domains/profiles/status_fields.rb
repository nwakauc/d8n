module Profiles
  # Viewer-relative status signals surfaced on discovery cards and profile
  # detail. These are real, per-request facts about each candidate — never
  # placeholder flavour — so the client can stop faking them:
  #
  #   verified       — the member has proven ownership of at least one contact
  #                    identifier (email/phone: IdentityIdentifier#verified_at).
  #                    This is NOT photo/identity ("it's really them") verification
  #                    — that domain does not exist yet. It is the honest, weaker
  #                    "reachable / contactable" signal we actually have today;
  #                    the caller decides how strongly to badge it.
  #   online         — the member has an active brand session used within
  #                    ONLINE_WINDOW. Reuses Matching::FacetFilter::ONLINE_WINDOW
  #                    on purpose so the "online" discovery *filter* and this
  #                    "online" *badge* can never disagree.
  #   last_active_at — the most recent such session use (ISO8601), or nil. Lets
  #                    the client render "active 3h ago" without a second signal.
  #   distance_km    — great-circle distance between the viewer and the member,
  #                    rounded to whole km with a 1km floor (never 0, which would
  #                    read as exact co-location). nil unless BOTH the viewer and
  #                    the member have a location no older than LOCATION_MAX_AGE.
  #   active_today   — the member had an active brand session within the last day
  #                    (derived from the same activity query as `online`).
  #   new_here       — the member's profile was created within NEW_HERE_WINDOW.
  #                    Derived from the profile row already in hand (no query).
  #   hook_tonight_active — the member currently has a live Hook Tonight state in
  #                    this brand (one bulk query for the whole page).
  #
  # Everything is computed in a fixed, small number of bulk queries regardless of
  # how many profiles are passed, so it can decorate a whole discovery page
  # without an N+1. All signals are read-only and safe to expose to any member
  # who could already see the profile.
  class StatusFields
    ONLINE_WINDOW = Matching::FacetFilter::ONLINE_WINDOW
    LOCATION_MAX_AGE = Matching::Strategies::Hookus::LOCATION_MAX_AGE
    EARTH_RADIUS_KM = Matching::EligibilityScope::EARTH_RADIUS_KM
    MIN_DISTANCE_KM = 1
    ACTIVE_TODAY_WINDOW = 24.hours
    NEW_HERE_WINDOW = 7.days

    def self.call(...)
      new(...).call
    end

    # `viewer` is the requesting member's Profile; `profiles` the candidates to
    # decorate (a single-element array is fine for the profile-detail path).
    def initialize(viewer:, profiles:)
      @viewer = viewer
      @profiles = Array(profiles)
    end

    def call
      return {} if viewer.nil? || profiles.empty?

      verified = verified_user_ids
      activity = last_active_by_user
      distances = distance_by_profile
      hook_tonight = hook_tonight_active_profile_ids
      online_threshold = ONLINE_WINDOW.ago
      active_today_threshold = ACTIVE_TODAY_WINDOW.ago
      new_here_threshold = NEW_HERE_WINDOW.ago

      profiles.each_with_object({}) do |profile, acc|
        last_active = activity[profile.user_id]
        acc[profile.id] = {
          verified: verified.include?(profile.user_id),
          online: last_active.present? && last_active >= online_threshold,
          active_today: last_active.present? && last_active >= active_today_threshold,
          new_here: profile.created_at.present? && profile.created_at >= new_here_threshold,
          hook_tonight_active: hook_tonight.include?(profile.id),
          last_active_at: last_active&.iso8601,
          distance_km: distances[profile.id]
        }
      end
    end

    private

    attr_reader :viewer, :profiles

    def user_ids
      @user_ids ||= profiles.map(&:user_id).uniq
    end

    # Identifiers are user-level (cross-brand), so verification is not
    # brand-scoped — proving you own an email once proves it everywhere.
    def verified_user_ids
      IdentityIdentifier.kept
        .where(user_id: user_ids)
        .where.not(verified_at: nil)
        .distinct
        .pluck(:user_id)
        .to_set
    end

    # Live Hook Tonight availability for the whole page in one query, brand-scoped
    # (HookTonightState.live re-checks expiry against the clock, so a stale row
    # never lights up). Mirrors HookTonight::CurrentState's liveness definition.
    def hook_tonight_active_profile_ids
      HookTonightState.live
        .where(brand_id: viewer.brand_id, profile_id: profiles.map(&:id))
        .distinct
        .pluck(:profile_id)
        .to_set
    end

    # Sessions are brand-scoped, so presence is too: being active on another
    # brand must not light you up here. Mirrors Matching::FacetFilter exactly.
    def last_active_by_user
      Session.active
        .where(brand_id: viewer.brand_id, user_id: user_ids)
        .group(:user_id)
        .maximum(:last_used_at)
    end

    def distance_by_profile
      origin = viewer_location
      return {} if origin.nil?

      candidate_locations.each_with_object({}) do |location, acc|
        km = haversine_km(origin.latitude, origin.longitude, location.latitude, location.longitude)
        acc[location.profile_id] = [ km.round, MIN_DISTANCE_KM ].max
      end
    end

    def viewer_location
      @viewer_location ||= ProfileLocation.kept
        .where(profile_id: viewer.id, brand_id: viewer.brand_id, captured_at: LOCATION_MAX_AGE.ago..)
        .order(captured_at: :desc)
        .first
    end

    # One kept location per profile (Profiles::CurrentLocation upserts), so this
    # returns at most one row per candidate.
    def candidate_locations
      ProfileLocation.kept.where(
        profile_id: profiles.map(&:id),
        brand_id: viewer.brand_id,
        captured_at: LOCATION_MAX_AGE.ago..
      )
    end

    def haversine_km(lat1, lon1, lat2, lon2)
      rad = Math::PI / 180
      phi1 = lat1.to_f * rad
      phi2 = lat2.to_f * rad
      d_phi = (lat2.to_f - lat1.to_f) * rad
      d_lambda = (lon2.to_f - lon1.to_f) * rad
      a = (Math.sin(d_phi / 2)**2) +
        (Math.cos(phi1) * Math.cos(phi2) * (Math.sin(d_lambda / 2)**2))
      EARTH_RADIUS_KM * 2 * Math.asin([ 1.0, Math.sqrt(a) ].min)
    end
  end
end
