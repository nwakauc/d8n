module Hooks
  # Bulk, viewer-relative 🔥 Hook button state for a set of candidate profiles,
  # used by discovery and profile detail so the client can label/disable the
  # action. Computed in a fixed number of queries regardless of page size (no
  # N+1). One of:
  #
  #   hooked      — an active Match already exists (whether it began as a Hook or a
  #                 mutual Like); the conversation is the surface, not a new Hook.
  #   pending     — the viewer has a live outgoing Hook awaiting this person's reply.
  #   unavailable — the viewer can't Hook: they already spent their one Hook on this
  #                 person (any terminal state), this person has a live Hook waiting
  #                 on the VIEWER (reply from the inbox instead), or the viewer has
  #                 already Liked them.
  #   available   — none of the above; the viewer may Hook.
  #
  # Deliberately does NOT distinguish declined/expired/blocked from one another —
  # they all collapse to `unavailable`, preserving recipient privacy.
  class ViewerStates
    AVAILABLE = "available".freeze
    PENDING = "pending".freeze
    HOOKED = "hooked".freeze
    UNAVAILABLE = "unavailable".freeze

    def self.call(...)
      new(...).call
    end

    def initialize(viewer:, profiles:)
      @viewer = viewer
      @profiles = Array(profiles)
    end

    def call
      return {} if viewer.nil? || profiles.empty?

      matched = matched_ids
      outgoing = outgoing_hooks_by_recipient
      incoming_live = incoming_live_sender_ids
      liked = liked_ids
      now = Time.current

      profiles.each_with_object({}) do |profile, acc|
        acc[profile.id] = state_for(profile.id, matched:, outgoing:, incoming_live:, liked:, now:)
      end
    end

    private

    attr_reader :viewer, :profiles

    def state_for(id, matched:, outgoing:, incoming_live:, liked:, now:)
      return HOOKED if matched.include?(id)

      hook = outgoing[id]
      return PENDING if hook && hook.status_pending? && hook.expires_at > now
      return UNAVAILABLE if hook # any terminal (or expired-pending) outgoing Hook
      return UNAVAILABLE if incoming_live.include?(id) || liked.include?(id)

      AVAILABLE
    end

    def profile_ids
      @profile_ids ||= profiles.map(&:id)
    end

    def matched_ids
      Match.kept.status_active.where(brand: viewer.brand)
        .where(
          "(profile_a_id = :v AND profile_b_id IN (:ids)) OR (profile_b_id = :v AND profile_a_id IN (:ids))",
          v: viewer.id, ids: profile_ids
        )
        .pluck(:profile_a_id, :profile_b_id)
        .map { |a, b| a == viewer.id ? b : a }
        .to_set
    end

    def outgoing_hooks_by_recipient
      Hook.kept.where(brand: viewer.brand, sender_profile: viewer, recipient_profile_id: profile_ids)
        .index_by(&:recipient_profile_id)
    end

    def incoming_live_sender_ids
      Hook.live.where(brand: viewer.brand, recipient_profile: viewer, sender_profile_id: profile_ids)
        .pluck(:sender_profile_id)
        .to_set
    end

    def liked_ids
      Like.kept.where(brand: viewer.brand, liker_profile: viewer, liked_profile_id: profile_ids)
        .pluck(:liked_profile_id)
        .to_set
    end
  end
end
